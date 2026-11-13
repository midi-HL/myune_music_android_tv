import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/network/google_drive_auth.dart';
import '../../services/network/remote_source.dart';

/// 一次 Google Drive 扫码配对的结果。
class DrivePairingResult {
  const DrivePairingResult({
    required this.name,
    required this.clientId,
    required this.clientSecret,
    required this.refreshToken,
    required this.rootFolderId,
    this.account = '',
  });

  final String name;
  final String clientId;
  final String clientSecret;
  final String refreshToken;
  final String rootFolderId;
  final String account;

  RemoteSource toSource(String id) => RemoteSource(
    id: id,
    name: name.trim().isEmpty ? '我的 Google Drive' : name.trim(),
    type: RemoteSourceType.googleDrive,
    host: '',
    port: 443,
    rootPath: '/',
    clientId: clientId.trim(),
    clientSecret: clientSecret.trim(),
    refreshToken: refreshToken.trim(),
    rootFolderId: rootFolderId.trim(),
  );
}

/// 电视端临时局域网配对服务。
///
/// 只在配对对话框打开期间监听，关闭即停；用一次性配对码防止局域网内其它设备
/// 误提交。凭据从手机 / 电脑直接 POST 到电视本机，不经过任何第三方服务。
class DrivePairingServer {
  DrivePairingServer({required this.onSubmit});

  /// 返回 null 表示成功，否则是可展示的错误文案。
  final Future<String?> Function(DrivePairingResult result) onSubmit;

  static const int _firstPort = 18780;
  static const int _portAttempts = 6;

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  late final String _pair;
  String? _address;
  int _port = _firstPort;
  bool _finished = false;

  String get pair => _pair;
  String get url => 'http://${_address ?? '127.0.0.1'}:$_port/?pair=$_pair';

  Future<void> start() async {
    _pair = _randomPair();
    final ip = await _lanAddress();
    if (ip == null) {
      throw StateError('未找到局域网地址，请确认电视已连接 WiFi / 网线');
    }
    _address = ip;
    HttpServer? server;
    for (var i = 0; i < _portAttempts; i++) {
      try {
        server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          _firstPort + i,
          shared: false,
        );
        _port = server.port;
        break;
      } on SocketException {
        // 端口占用则顺延。
      }
    }
    if (server == null) {
      throw StateError('配对端口 $_firstPort 起均被占用，请稍后重试');
    }
    _server = server;
    // HttpServer.listen() 返回 StreamSubscription<HttpRequest>，不是 Future；
    // 保留引用以便 stop() 时取消，避免服务关闭后仍回调 _handle。
    _subscription = server.listen(_handle);
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.add('Access-Control-Allow-Origin', '*');
    response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type');
    try {
      if (request.method == 'OPTIONS') {
        response.statusCode = HttpStatus.ok;
        await response.close();
        return;
      }
      final path = request.uri.path;
      if (path == '/ping') {
        _json(response, HttpStatus.ok, <String, dynamic>{
          'ok': true,
          'app': 'starnote',
          'pair': _pair,
        });
        return;
      }
      if (path == '/' || path == '/index.html') {
        response.statusCode = HttpStatus.ok;
        response.headers.contentType = ContentType.html;
        response.write(_page.replaceAll('__PAIR__', _pair));
        await response.close();
        return;
      }
      if (path == '/submit' && request.method == 'POST') {
        if (_finished) {
          _json(response, HttpStatus.gone, <String, dynamic>{
            'ok': false,
            'error': '本次配对已完成，请在电视上重新打开配对页',
          });
          return;
        }
        final raw = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          _json(response, HttpStatus.badRequest, <String, dynamic>{
            'ok': false,
            'error': '提交格式不是 JSON 对象',
          });
          return;
        }
        final data = Map<String, dynamic>.from(decoded);
        if ((data['pair'] ?? '').toString() != _pair) {
          _json(response, HttpStatus.forbidden, <String, dynamic>{
            'ok': false,
            'error': '配对码不正确，请重新扫码',
          });
          return;
        }
        String text(String key) => (data[key] ?? '').toString().trim();
        final clientId = text('clientId');
        final refreshToken = text('refreshToken');
        if (clientId.isEmpty || refreshToken.isEmpty) {
          _json(response, HttpStatus.badRequest, <String, dynamic>{
            'ok': false,
            'error': 'client_id 与 refresh_token 不能为空',
          });
          return;
        }
        final result = DrivePairingResult(
          name: text('name'),
          clientId: clientId,
          clientSecret: text('clientSecret'),
          refreshToken: refreshToken,
          rootFolderId: text('rootFolderId'),
        );
        final error = await onSubmit(result);
        if (error != null) {
          _json(response, HttpStatus.badRequest, <String, dynamic>{
            'ok': false,
            'error': error,
          });
          return;
        }
        _finished = true;
        _json(response, HttpStatus.ok, <String, dynamic>{'ok': true});
        return;
      }
      _json(response, HttpStatus.notFound, <String, dynamic>{
        'ok': false,
        'error': 'not found',
      });
    } catch (error) {
      _json(response, HttpStatus.internalServerError, <String, dynamic>{
        'ok': false,
        'error': '$error',
      });
    }
  }

  void _json(HttpResponse response, int status, Map<String, dynamic> body) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    unawaited(response.close());
  }

  static Future<String?> _lanAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) return address.address;
        }
      }
    } catch (_) {}
    return null;
  }

  static String _randomPair() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(
      6,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }
}

/// 电视上的扫码配对对话框：二维码 + 局域网地址 + 配对码 + 取消按钮。
/// 全部控件十字键可达；配对成功返回 [DrivePairingResult]。
Future<DrivePairingResult?> showDrivePairingDialog(BuildContext context) {
  return showDialog<DrivePairingResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _DrivePairingDialog(),
  );
}

class _DrivePairingDialog extends StatefulWidget {
  const _DrivePairingDialog();

  @override
  State<_DrivePairingDialog> createState() => _DrivePairingDialogState();
}

class _DrivePairingDialogState extends State<_DrivePairingDialog> {
  DrivePairingServer? _server;
  String? _error;
  bool _ready = false;
  DrivePairingResult? _paired;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final server = DrivePairingServer(onSubmit: _onSubmit);
    try {
      await server.start();
      if (!mounted) {
        await server.stop();
        return;
      }
      setState(() {
        _server = server;
        _ready = true;
      });
    } catch (error) {
      await server.stop();
      if (mounted) setState(() => _error = '$error');
    }
  }

  /// 提交时立刻用 refresh_token 换一次 access_token 并读账号信息，
  /// 凭据不对就在手机配页上直接报错，不会悄悄存进电视。
  Future<String?> _onSubmit(DrivePairingResult result) async {
    try {
      final probe = result.toSource('pairing-probe');
      final account = await GoogleDriveAuth.accountLabel(probe);
      GoogleDriveAuth.invalidate(probe.id);
      if (!mounted) return '电视已关闭配对页';
      if (!_finished) {
        _finished = true;
        // 不在这里 pop：HTTP 响应还没写回手机，立刻关闭页面会让配页
        // 只看到网络错误。改为显示成功态，由用户按「完成」关闭。
        setState(() {
          _paired = DrivePairingResult(
            name: result.name,
            clientId: result.clientId,
            clientSecret: result.clientSecret,
            refreshToken: result.refreshToken,
            rootFolderId: result.rootFolderId,
            account: account,
          );
        });
      }
      return null;
    } catch (error) {
      return '凭据校验失败：$error';
    }
  }

  bool _finished = false;

  @override
  void dispose() {
    unawaited(_server?.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final server = _server;
    return AlertDialog(
      title: const Text('扫码配对 Google Drive（只读）'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            if (_paired != null) ...<Widget>[
              Icon(Icons.check_circle, size: 64, color: scheme.primary),
              const SizedBox(height: 12),
              Text(
                '配对成功 · ${_paired!.account.isEmpty ? 'Google 账号' : _paired!.account}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '凭据已保存在电视本机。按「完成」返回网络源列表。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ] else if (_ready && server != null) ...<Widget>[
              Container(
                width: 190,
                height: 190,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: QrImageView(
                  data: server.url,
                  version: QrVersions.auto,
                  size: 174,
                  padding: const EdgeInsets.all(6),
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '用手机扫码，或在同一 WiFi 下打开：',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              SelectableText(
                server.url,
                style: const TextStyle(fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                '配对码 ${server.pair}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '只请求 drive.readonly 只读权限。凭据直接提交到这台电视，'
                '不经过任何第三方服务；配对页关闭后服务立即停止。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ] else if (_error != null)
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.error),
              )
            else
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        if (_paired == null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          )
        else
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(_paired),
            child: const Text('完成'),
          ),
      ],
    );
  }
}

/// 自包含配页：手机 / 电脑在同一 WiFi 下打开，填好凭据后直接 POST 回电视。
/// 用原始字符串，避免 Dart 字符串插值把 JS / CSS 里的 $ 吃掉。
const String _page = r'''<!DOCTYPE html>
<html lang="zh-CN"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>星音 StarNote · Google Drive 配对</title>
<style>
:root{color-scheme:dark;
 --bg:#121418;--surface:#1E222A;--surface2:#171A21;--line:#333842;
 --primary:#8AB4F8;--on:#E6E8EF;--muted:#8A919E}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--on);
 font:15px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
 padding-bottom:32px}
.appbar{display:flex;align-items:center;gap:10px;flex-wrap:wrap;
 padding:14px 18px;background:var(--surface2);border-bottom:1px solid var(--line);
 position:sticky;top:0;z-index:5}
.brand{font-size:17px;font-weight:700;letter-spacing:.2px}
.sub{font-size:13px;color:var(--muted)}
.badge{margin-left:auto;font-size:11px;color:var(--primary);
 border:1px solid var(--line);border-radius:999px;padding:3px 10px;white-space:nowrap}
main{max-width:620px;margin:0 auto;padding:18px}
.steps{display:flex;gap:8px;margin-bottom:16px}
.step{flex:1;text-align:center;font-size:12px;color:var(--muted);
 background:var(--surface2);border:1px solid var(--line);border-radius:12px;padding:8px 4px}
.step.active{color:var(--primary);border-color:var(--primary);background:#1c2433}
.card{background:var(--surface);border:1px solid var(--line);
 border-radius:18px;padding:20px;margin-bottom:14px;
 box-shadow:0 6px 20px rgba(0,0,0,.22)}
.card.secondary{background:var(--surface2)}
h1{font-size:19px;margin:0 0 6px}
h2{font-size:15px;margin:0 0 6px;color:var(--primary)}
p{color:var(--muted);font-size:13px;margin:6px 0 14px}
label{display:block;margin:14px 0 5px;font-size:12px;color:#C7CBD6}
input,textarea{width:100%;padding:11px 12px;border-radius:12px;
 border:1px solid var(--line);background:var(--surface2);color:#fff;
 font:13px ui-monospace,SFMono-Regular,Menlo,monospace;outline:none}
input:focus,textarea:focus{border-color:var(--primary)}
textarea{resize:vertical}
button{margin-top:20px;width:100%;padding:13px;border:0;border-radius:14px;
 background:var(--primary);color:#10141c;font-size:15px;font-weight:700;cursor:pointer}
button:active{transform:translateY(1px)}
#msg{margin-top:12px;min-height:20px;font-size:13px}
code{background:#2a2d3a;padding:1px 5px;border-radius:5px;color:#cdd7f0}
.hint{margin-top:4px;font-size:12px;line-height:1.7}
</style></head><body>
<header class="appbar">
  <span class="brand">星音 StarNote</span>
  <span class="sub">Google Drive 配对</span>
  <span class="badge">只读 · 本机配对</span>
</header>
<main>
  <div class="steps">
    <div class="step active">1 设置</div>
    <div class="step">2 授权</div>
    <div class="step">3 配对</div>
  </div>
  <section class="card">
    <h1>把凭据交给电视</h1>
    <p>凭据会<b>直接提交到这台电视</b>（局域网），不经过任何第三方服务。
    应用只请求 <code>drive.readonly</code> 只读权限，不会上传、重命名或删除任何文件。</p>
    <label>名称</label><input id="name" value="我的 Google Drive">
    <label>OAuth client_id *</label><input id="clientId" placeholder="xxxxxxxx.apps.googleusercontent.com">
    <label>client_secret（桌面应用类型需要，可留空）</label><input id="clientSecret">
    <label>refresh_token *</label><textarea id="refreshToken" rows="3"></textarea>
    <label>根文件夹 ID（留空 = 我的云端硬盘）</label><input id="rootFolderId">
    <input type="hidden" id="pair" value="__PAIR__">
    <button id="go">提交到电视</button>
    <div id="msg"></div>
  </section>
  <section class="card secondary">
    <h2>怎么拿到 refresh_token</h2>
    <p class="hint">电脑端推荐用仓库里的 <b>Google Drive 配对助手</b>（Go/Fyne 图形程序）：
    设置一次 client_id，点「打开浏览器授权」自动完成，再点「与电视配对」即可，
    本页无需手动填写。<br>
    只有手机时，可用 <code>tools/gdrive_auth.py</code> 或 Google OAuth Playground
    生成 refresh_token 后粘贴到上面。<br>
    注意：Testing 状态签发的 refresh_token <b>7 天过期</b>，到期重新授权一次即可。</p>
  </section>
</main>
<script>
var msg=document.getElementById('msg');
document.getElementById('go').onclick=async function(){
  var v=function(id){return document.getElementById(id).value.trim()};
  var body={name:v('name'),clientId:v('clientId'),clientSecret:v('clientSecret'),
    refreshToken:v('refreshToken'),rootFolderId:v('rootFolderId'),pair:v('pair')};
  if(!body.clientId||!body.refreshToken){msg.style.color='#ff9d9d';msg.textContent='请填写 client_id 与 refresh_token';return}
  msg.style.color='#8AB4F8';msg.textContent='正在校验凭据…';
  try{
    var r=await fetch('/submit',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify(body)});
    var j=await r.json();
    if(j.ok){msg.style.color='#7ee2a8';msg.textContent='配对成功，请回到电视按「完成」'}
    else{msg.style.color='#ff9d9d';msg.textContent=j.error||'提交失败'}
  }catch(e){msg.style.color='#ff9d9d';msg.textContent='无法连接电视：'+e}
};
</script></body></html>''';
