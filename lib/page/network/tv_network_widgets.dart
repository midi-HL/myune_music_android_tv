import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/network/bilibili_client.dart';
import '../../services/network/remote_media_registry.dart';
import '../../services/network/remote_source.dart';
import '../../tv/tv_focus_nav.dart';

/// 网络媒体页共用的电视端控件。
///
/// 设计约束（针对 Android TV）：
/// 1. 每个可交互项都同时支持鼠标/触控（GestureDetector.onTap）与遥控器/键盘/手柄
///    （TvFocusHighlight.onActivate），不使用裸 GestureDetector；
/// 2. 需要打字的地方一律走「字段按钮 → 弹出单字段输入对话框」，对话框里的
///    TextField autofocus 并显式请求 TextInput.show，保证软键盘一定弹出；
///    方向键在软键盘里选字，「完成 / 搜索」或「确定」按钮提交；
/// 3. 所有对话框内的按钮同样用 TvFocusHighlight，焦点被锁在当前模态层内。

class TvActionButton extends StatelessWidget {
  const TvActionButton({
    required this.label,
    required this.onPressed,
    this.value,
    this.icon,
    this.autofocus = false,
    this.selected = false,
    this.enabled = true,
    this.debugLabel,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final String? value;
  final IconData? icon;
  final bool autofocus;
  final bool selected;
  final bool enabled;
  final String? debugLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1.0 : 0.42,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onPressed : null,
          child: TvFocusHighlight(
            autofocus: autofocus,
            debugLabel: debugLabel ?? 'tv-net-btn-$label',
            onActivate: enabled ? onPressed : null,
            builder: (context, focused) {
              Color background;
              if (focused) {
                background = scheme.primary.withValues(alpha: 0.30);
              } else if (selected) {
                background = scheme.primary.withValues(alpha: 0.16);
              } else {
                background = scheme.surfaceContainerHighest
                    .withValues(alpha: 0.55);
              }
              return AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                constraints: const BoxConstraints(minHeight: 46),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(9),
                ),
                // AlertDialog.actions 由 OverflowBar 布局，主轴宽度是无界的；
                // Row 里若有 Spacer / Flexible（flex>0）会直接抛
                // “RenderFlex children have non-zero flex but incoming width
                // constraints are unbounded”。因此在无界宽度时退化成自适应宽度、
                // 无 flex 子项的紧凑行；有界宽度（列表 / 固定宽度容器）时仍保留
                // 右对齐数值的原本外观。
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final spread = constraints.hasBoundedWidth;
                    final Widget? valueWidget = value == null
                        ? null
                        : ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: Text(
                              value!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          );
                    return Row(
                      mainAxisSize:
                          spread ? MainAxisSize.max : MainAxisSize.min,
                      children: <Widget>[
                        if (icon != null) ...<Widget>[
                          Icon(icon, size: 19, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 10),
                        ],
                        if (spread)
                          Flexible(child: _labelText(scheme))
                        else
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: _labelText(scheme),
                          ),
                        if (valueWidget != null) ...<Widget>[
                          if (spread)
                            const Spacer()
                          else
                            const SizedBox(width: 10),
                          if (spread)
                            Flexible(child: valueWidget)
                          else
                            valueWidget,
                        ],
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Text _labelText(ColorScheme scheme) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, color: scheme.onSurface),
    );
  }
}

/// 显式请求软键盘。部分 Android TV 启动器不会在 TextField 获焦时自动弹出 IME，
/// 因此在对话框打开后的下一帧补一次 TextInput.show。
void requestTvKeyboard() {
  try {
    SystemChannels.textInput.invokeMethod('TextInput.show');
  } catch (_) {
    // 输入法不可用时（例如外接物理键盘）忽略。
  }
}

const String _kTvInputHint =
    '按遥控器 OK 唤出软键盘；方向键在软键盘上选字，OK 确认，'
    '按「完成 / 搜索」或下方「确定」提交。';

/// 单字段文本输入对话框。返回 null 表示取消。
Future<String?> showTvTextInput({
  required BuildContext context,
  required String title,
  String? hint,
  String initialValue = '',
  bool obscureText = false,
  TextInputType keyboardType = TextInputType.text,
  String confirmLabel = '确定',
  String? helper,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => _TvTextInputDialog(
      title: title,
      hint: hint,
      initialValue: initialValue,
      obscureText: obscureText,
      keyboardType: keyboardType,
      confirmLabel: confirmLabel,
      helper: helper,
    ),
  );
}

class _TvTextInputDialog extends StatefulWidget {
  const _TvTextInputDialog({
    required this.title,
    required this.initialValue,
    required this.obscureText,
    required this.keyboardType,
    required this.confirmLabel,
    this.hint,
    this.helper,
  });

  final String title;
  final String initialValue;
  final bool obscureText;
  final TextInputType keyboardType;
  final String confirmLabel;
  final String? hint;
  final String? helper;

  @override
  State<_TvTextInputDialog> createState() => _TvTextInputDialogState();
}

class _TvTextInputDialogState extends State<_TvTextInputDialog> {
  late final TextEditingController _controller;
  final FocusNode _fieldNode = FocusNode(debugLabel: 'tv-network-text-field');

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.selection = TextSelection.collapsed(
      offset: widget.initialValue.length,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusScope.of(context).requestFocus(_fieldNode);
      requestTvKeyboard();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _fieldNode.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _controller,
              focusNode: _fieldNode,
              autofocus: true,
              obscureText: widget.obscureText,
              keyboardType: widget.keyboardType,
              textInputAction: TextInputAction.done,
              maxLines: 1,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: widget.hint,
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              onTap: requestTvKeyboard,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 10),
            Text(
              widget.helper ?? _kTvInputHint,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TvActionButton(
          label: '取消',
          onPressed: () => Navigator.of(context).pop(),
        ),
        TvActionButton(label: widget.confirmLabel, onPressed: _submit),
      ],
    );
  }
}

/// 简单提示 / 确认对话框，全部按钮遥控器可达。
Future<void> showTvAlert(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('提示', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 380,
        child: Text(message, style: const TextStyle(fontSize: 13)),
      ),
      actions: <Widget>[
        TvActionButton(
          label: '关闭',
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
  );
}

Future<bool> showTvConfirm(BuildContext context, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('请确认', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 380,
        child: Text(message, style: const TextStyle(fontSize: 13)),
      ),
      actions: <Widget>[
        TvActionButton(
          label: '取消',
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        TvActionButton(
          label: '确定',
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  return result == true;
}

/// 网络源编辑对话框。每个字段都是遥控器可达的按钮，按 OK 才弹输入对话框，
/// 避免在 TV 上出现方向键被困在多个 TextField 里无法移动焦点的问题。
Future<RemoteSource?> showTvSourceEditor({
  required BuildContext context,
  RemoteSource? existing,
}) {
  return showDialog<RemoteSource>(
    context: context,
    builder: (BuildContext dialogContext) =>
        _TvSourceEditorDialog(existing: existing),
  );
}

class _TvSourceEditorDialog extends StatefulWidget {
  const _TvSourceEditorDialog({this.existing});

  final RemoteSource? existing;

  @override
  State<_TvSourceEditorDialog> createState() => _TvSourceEditorDialogState();
}

class _TvSourceEditorDialogState extends State<_TvSourceEditorDialog> {
  late final String _id;
  late RemoteSourceType _type;
  late bool _useTls;
  late String _name;
  late String _host;
  late String _port;
  late String _root;
  late String _username;
  late String _password;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _id = existing?.id ?? 'src-${DateTime.now().microsecondsSinceEpoch}';
    _type = existing?.type ?? RemoteSourceType.webdav;
    _useTls = existing?.useTls ?? false;
    _name = existing?.name ?? '我的网盘';
    _host = existing?.host ?? '';
    _port = (existing?.port ?? RemoteSource.defaultPort(_type, _useTls))
        .toString();
    _root = existing?.rootPath ?? '/';
    _username = existing?.username ?? '';
    _password = existing?.password ?? '';
  }

  Future<void> _edit({
    required String title,
    required String current,
    required ValueChanged<String> onSaved,
    String? hint,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
  }) async {
    final value = await showTvTextInput(
      context: context,
      title: title,
      initialValue: current,
      hint: hint,
      obscureText: obscureText,
      keyboardType: keyboardType,
    );
    if (value != null && mounted) {
      setState(() => onSaved(value));
    }
  }

  void _toggleType() {
    setState(() {
      final previousDefault = RemoteSource.defaultPort(_type, _useTls);
      _type = _type == RemoteSourceType.webdav
          ? RemoteSourceType.ftp
          : RemoteSourceType.webdav;
      if (_port.trim() == previousDefault.toString()) {
        _port = RemoteSource.defaultPort(_type, _useTls).toString();
      }
      if (_type == RemoteSourceType.ftp) _useTls = false;
    });
  }

  void _toggleTls() {
    setState(() {
      final previousDefault = RemoteSource.defaultPort(_type, _useTls);
      _useTls = !_useTls;
      if (_port.trim() == previousDefault.toString()) {
        _port = RemoteSource.defaultPort(_type, _useTls).toString();
      }
    });
  }

  void _save() {
    final host = _host.trim();
    final port = int.tryParse(_port.trim());
    if (host.isEmpty) {
      showTvAlert(context, '服务器地址不能为空');
      return;
    }
    if (port == null || port <= 0 || port > 65535) {
      showTvAlert(context, '端口必须是 1-65535 之间的数字');
      return;
    }
    var root = _root.trim();
    if (root.isEmpty) root = '/';
    if (!root.startsWith('/')) root = '/$root';
    Navigator.of(context).pop(
      RemoteSource(
        id: _id,
        name: _name.trim().isEmpty ? '未命名' : _name.trim(),
        type: _type,
        host: host,
        port: port,
        rootPath: root,
        username: _username.trim(),
        password: _password,
        useTls: _type == RemoteSourceType.webdav && _useTls,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(
        widget.existing == null ? '添加网络音乐源' : '编辑网络音乐源',
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '支持 WebDAV（名称以 web 开头的网络硬盘协议）与 FTP。'
                '只按需拉流、不占用电视本地存储。',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              TvActionButton(
                label: '协议',
                value: remoteSourceTypeLabel(_type),
                icon: Icons.lan_outlined,
                autofocus: true,
                onPressed: _toggleType,
              ),
              const SizedBox(height: 6),
              TvActionButton(
                label: '名称',
                value: _name,
                icon: Icons.label_outline,
                onPressed: () => _edit(
                  title: '名称',
                  current: _name,
                  onSaved: (v) => _name = v,
                ),
              ),
              const SizedBox(height: 6),
              TvActionButton(
                label: '服务器地址',
                value: _host.isEmpty ? '未设置（例如 192.168.1.10）' : _host,
                icon: Icons.dns_outlined,
                onPressed: () => _edit(
                  title: '服务器地址',
                  current: _host,
                  hint: 'IP 或域名，不要带 http://',
                  keyboardType: TextInputType.url,
                  onSaved: (v) => _host = v,
                ),
              ),
              const SizedBox(height: 6),
              TvActionButton(
                label: '端口',
                value: _port,
                icon: Icons.numbers,
                onPressed: () => _edit(
                  title: '端口',
                  current: _port,
                  keyboardType: TextInputType.number,
                  onSaved: (v) => _port = v,
                ),
              ),
              const SizedBox(height: 6),
              TvActionButton(
                label: '根目录',
                value: _root,
                icon: Icons.folder_outlined,
                onPressed: () => _edit(
                  title: '根目录',
                  current: _root,
                  hint: '例如 /music/ 或 /remote.php/dav/files/user/',
                  onSaved: (v) => _root = v,
                ),
              ),
              const SizedBox(height: 6),
              TvActionButton(
                label: '用户名',
                value: _username.isEmpty ? '匿名' : _username,
                icon: Icons.person_outline,
                onPressed: () => _edit(
                  title: '用户名（留空为匿名）',
                  current: _username,
                  onSaved: (v) => _username = v,
                ),
              ),
              const SizedBox(height: 6),
              TvActionButton(
                label: '密码',
                value: _password.isEmpty ? '未设置' : '••••••',
                icon: Icons.lock_outline,
                onPressed: () => _edit(
                  title: '密码',
                  current: _password,
                  obscureText: true,
                  onSaved: (v) => _password = v,
                ),
              ),
              if (_type == RemoteSourceType.webdav) ...<Widget>[
                const SizedBox(height: 6),
                TvActionButton(
                  label: 'HTTPS（WebDAV over TLS）',
                  value: _useTls ? '开启' : '关闭（HTTP）',
                  icon: Icons.https_outlined,
                  onPressed: _toggleTls,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TvActionButton(
          label: '取消',
          onPressed: () => Navigator.of(context).pop(),
        ),
        TvActionButton(label: '保存', onPressed: _save),
      ],
    );
  }
}

/// B 站二维码扫码登录对话框。全程无需打字：遥控器只需看二维码、等状态，
/// 用「刷新二维码 / 退出登录 / 关闭」三个按钮即可完成所有操作。
Future<bool> showTvQrLogin({required BuildContext context}) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => const _TvQrLoginDialog(),
  );
  return changed == true;
}

class _TvQrLoginDialog extends StatefulWidget {
  const _TvQrLoginDialog();

  @override
  State<_TvQrLoginDialog> createState() => _TvQrLoginDialogState();
}

class _TvQrLoginDialogState extends State<_TvQrLoginDialog> {
  Timer? _pollTimer;
  BiliQrCode? _qr;
  BiliQrState _state = BiliQrState.waiting;
  String _message = '正在生成登录二维码…';
  bool _loggedIn = false;
  bool _busy = false;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _loggedIn = BiliAuthStore.instance.isLoggedIn;
    if (!_loggedIn) _start();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _pollTimer?.cancel();
    _polling = false;
    setState(() {
      _busy = true;
      _state = BiliQrState.waiting;
      _message = '正在生成登录二维码…';
      _qr = null;
    });
    try {
      final qr = await BiliClient.instance.generateQrCode();
      if (!mounted) return;
      setState(() {
        _qr = qr;
        _state = BiliQrState.waiting;
        _message = '请用哔哩哔哩手机 App 扫描二维码';
        _busy = false;
      });
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _state = BiliQrState.error;
        _message = '生成二维码失败：$error';
        _busy = false;
      });
    }
  }

  Future<void> _poll() async {
    final qr = _qr;
    // 网络慢时 2 秒的 Timer.periodic 可能叠加多次轮询，用 _polling 去重，
    // 避免并发写状态 / 重复保存 Cookie。
    if (qr == null || _busy || _polling) return;
    _polling = true;
    try {
      final result = await BiliClient.instance.pollQrCode(qr.qrcodeKey);
      if (!mounted) return;
      setState(() {
        _state = result.state;
        _message = result.message ?? _message;
      });
      if (result.state == BiliQrState.success) {
        _pollTimer?.cancel();
        setState(() {
          _loggedIn = true;
          _message = '登录成功，已保存登录态';
        });
        Future<void>.delayed(const Duration(milliseconds: 900), () {
          if (mounted) Navigator.of(context).pop(true);
        });
      } else if (result.state == BiliQrState.expired ||
          result.state == BiliQrState.error) {
        _pollTimer?.cancel();
      }
    } catch (error) {
      if (!mounted) return;
      _pollTimer?.cancel();
      setState(() {
        _state = BiliQrState.error;
        _message = '轮询登录状态失败：$error';
      });
    } finally {
      _polling = false;
    }
  }

  Future<void> _logout() async {
    await BiliAuthStore.instance.clear();
    if (!mounted) return;
    setState(() {
      _loggedIn = false;
      _state = BiliQrState.waiting;
      _message = '已退出登录，可重新扫码';
      _qr = null;
    });
    await _start();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canRefresh =
        !_busy && (_state == BiliQrState.expired || _state == BiliQrState.error);
    return AlertDialog(
      title: const Text('哔哩哔哩扫码登录', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 230,
              height: 230,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: _qr != null && !_loggedIn
                  ? QrImageView(
                      data: _qr!.url,
                      version: QrVersions.auto,
                      size: 210,
                      padding: const EdgeInsets.all(6),
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    )
                  : Icon(
                      _loggedIn ? Icons.check_circle : Icons.qr_code_2,
                      size: 72,
                      color: _loggedIn ? Colors.green : scheme.outline,
                    ),
            ),
            const SizedBox(height: 14),
            Text(
              _message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              '登录只用于获取更高音质与受限内容；不登录也可搜索和播放。'
              '登录态仅保存在本机。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        if (canRefresh)
          TvActionButton(label: '刷新二维码', autofocus: true, onPressed: _start),
        if (_loggedIn)
          TvActionButton(label: '退出登录', onPressed: _logout),
        TvActionButton(
          label: '关闭',
          // 已登录 / 正常等待时也要有一个初始焦点，保证遥控器 OK 始终能落到
          // 弹窗内的按钮上，不会出现「有弹窗但没有可聚焦控件」的死角。
          autofocus: !canRefresh,
          onPressed: () => Navigator.of(context).pop(_loggedIn),
        ),
      ],
    );
  }
}

// ===== 通用「更多」菜单 / 紧凑控件 / 网络封面 =====

class TvMenuItem<T> {
  const TvMenuItem({
    required this.value,
    required this.label,
    this.valueText,
    this.icon,
    this.enabled = true,
  });

  final T value;
  final String label;
  final String? valueText;
  final IconData? icon;
  final bool enabled;
}

/// 通用单列菜单对话框。所有条目都是遥控器可达的 TvActionButton，
/// 用于把原来平铺在页面上的次要功能收进「更多」层级。
Future<T?> showTvMenu<T>({
  required BuildContext context,
  required String title,
  required List<TvMenuItem<T>> items,
}) {
  final firstEnabled = items.indexWhere((TvMenuItem<T> item) => item.enabled);
  return showDialog<T>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: TvActionButton(
                    label: items[i].label,
                    value: items[i].valueText,
                    icon: items[i].icon,
                    enabled: items[i].enabled,
                    autofocus: i == firstEnabled,
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(items[i].value),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TvActionButton(
          label: '关闭',
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
  );
}

/// 紧凑的图标按钮：用于「上一页 / 下一页」这类只需要一行高度的操作，
/// 同样同时支持遥控器 OK 与鼠标 / 触控。
class TvIconButton extends StatelessWidget {
  const TvIconButton({
    required this.icon,
    required this.onPressed,
    this.semanticLabel,
    this.enabled = true,
    this.autofocus = false,
    this.size = 34,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? semanticLabel;
  final bool enabled;
  final bool autofocus;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onPressed : null,
          child: TvFocusHighlight(
            autofocus: autofocus,
            debugLabel: semanticLabel ?? 'tv-net-icon',
            onActivate: enabled ? onPressed : null,
            builder: (BuildContext context, bool focused) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: size + 10,
                height: size + 10,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: focused
                      ? scheme.primary.withValues(alpha: 0.30)
                      : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: size - 8,
                  color: focused ? scheme.primary : scheme.onSurfaceVariant,
                  semanticLabel: semanticLabel,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 网络媒体的封面：优先用 Song 里已保存的字节，其次按需从 URL 编码的
/// 封面地址下载（走本机代理，WebDAV / FTP / B 站 CDN 鉴权都被代理补齐）。
/// 下载失败时显示占位图标，不影响列表与播放。
class RemoteArtwork extends StatefulWidget {
  const RemoteArtwork({
    required this.mediaUrl,
    this.size = 44,
    this.placeholder = Icons.music_note_outlined,
    super.key,
  });

  final String mediaUrl;
  final double size;
  final IconData placeholder;

  @override
  State<RemoteArtwork> createState() => _RemoteArtworkState();
}

class _RemoteArtworkState extends State<RemoteArtwork> {
  Uint8List? _bytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RemoteArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaUrl != widget.mediaUrl) {
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    final cached = RemoteMediaRegistry.cachedArtwork(widget.mediaUrl);
    if (cached != null && cached.isNotEmpty) {
      if (mounted) setState(() => _bytes = cached);
      return;
    }
    final song = RemoteMediaRegistry.lookup(widget.mediaUrl);
    if (song?.albumArt != null && song!.albumArt!.isNotEmpty) {
      if (mounted) setState(() => _bytes = song.albumArt);
      return;
    }
    if (_loading) return;
    _loading = true;
    try {
      final bytes = await RemoteMediaRegistry.artworkFor(widget.mediaUrl);
      if (mounted && bytes != null && bytes.isNotEmpty) {
        setState(() => _bytes = bytes);
      }
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _bytes != null
            ? Image.memory(
                _bytes!,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            : ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Icon(
                  widget.placeholder,
                  size: widget.size * 0.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}
