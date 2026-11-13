#!/usr/bin/env python3
"""星音 StarNote · Google Drive 只读授权助手（Python 标准库，零依赖）。

用途
----
Android TV 通常没有系统浏览器，Google 的 OAuth 设备码流程又不支持
`drive.readonly`，因此由本脚本在**电脑 / 手机**上完成一次标准 OAuth
loopback 登录，拿到 refresh_token 后自动 POST 到电视上的配对页。

前提
----
1. 在 Google Cloud Console 创建 OAuth 客户端，类型选「桌面应用」(Desktop app)。
   - 客户端 ID 形如 `xxxx.apps.googleusercontent.com`
   - 客户端密钥（Desktop 类型也会有，但不属于机密；本脚本只在本地使用）
2. 在 OAuth 同意屏幕把「Google Drive API」的
   `https://www.googleapis.com/auth/drive.readonly` 加为测试范围，
   并把你自己的 Google 账号加进「测试用户」（未做 OAuth 验证的应用要求）。
3. 电视与电脑处于同一 WiFi。

用法
----
    python tools/gdrive_auth.py \
        --client-id "xxxx.apps.googleusercontent.com" \
        --client-secret "GOCSPX-xxxx" \
        --pair-url "http://192.168.1.20:18780/?pair=AB3D7K"

`--pair-url` 就是电视配对页上显示的二维码内容 / 网址。
省略 `--client-secret` 时只发 client_id（部分客户端类型可行）。

也可用环境变量 GDRIVE_CLIENT_ID / GDRIVE_CLIENT_SECRET 代替参数。

安全说明
--------
- refresh_token 只提交到局域网里这台电视，不经过任何第三方服务。
- 脚本不保存任何凭据到磁盘；完成后请把 Cloud Console 的密钥当作普通配置保管。
- 电视端只请求 drive.readonly，不会上传、重命名或删除任何文件。

重授权（约每 7 天一次）
----------------------
测试状态 (Testing) 的 Cloud 项目签发的 refresh_token 会在 7 天后过期，
refresh_token 换取 access_token 时 Google 返回 invalid_grant。此时无需改任何
配置，只需：
  1. 在电视上重新打开「添加 Google Drive」，取得新的二维码 / --pair-url；
  2. 用原来的 --client-id / --client-secret 再跑一次本脚本即可。
--pair-url 也可以省略，脚本会提示从电视上复制；--client-id / --client-secret
可通过环境变量 GDRIVE_CLIENT_ID / GDRIVE_CLIENT_SECRET 固定，方便重复执行。
"""

import argparse
import http.server
import json
import os
import secrets
import threading
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
SCOPE = "https://www.googleapis.com/auth/drive.readonly"
PORT = 53682
REDIRECT_URI = f"http://127.0.0.1:{PORT}/"


class _Handler(http.server.BaseHTTPRequestHandler):
    result = None  # type: dict | None
    state = ""

    def do_GET(self):  # noqa: N802
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        if query.get("state", [""])[0] != _Handler.state:
            self._reply(400, "state 校验失败")
            return
        if "error" in query:
            self._reply(400, "授权被拒绝：" + query["error"][0])
            return
        code = query.get("code", [""])[0]
        if not code:
            self._reply(400, "未收到授权码")
            return
        _Handler.result = {"code": code}
        self._reply(200, "授权完成，可以关闭本页，回到命令行。")

    def _reply(self, status, text):
        body = ("<html><meta charset='utf-8'><body style='font:16px sans-serif;"
                "padding:40px'>%s</body></html>" % text).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


def _exchange(code, client_id, client_secret):
    data = {
        "code": code,
        "client_id": client_id,
        "grant_type": "authorization_code",
        "redirect_uri": REDIRECT_URI,
    }
    if client_secret:
        data["client_secret"] = client_secret
    req = urllib.request.Request(
        TOKEN_URL,
        data=urllib.parse.urlencode(data).encode(),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def _submit(pair_url, payload):
    parsed = urllib.parse.urlparse(pair_url)
    pair = urllib.parse.parse_qs(parsed.query).get("pair", [""])[0]
    if not pair:
        raise SystemExit("配对地址里没有 pair 参数，请从电视上重新扫码")
    post_url = urllib.parse.urlunparse(
        (parsed.scheme, parsed.netloc, "/submit", "", "", "")
    )
    body = dict(payload)
    body["pair"] = pair
    req = urllib.request.Request(
        post_url,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def main():
    ap = argparse.ArgumentParser(description="Google Drive 只读授权助手")
    ap.add_argument("--client-id", default=os.environ.get("GDRIVE_CLIENT_ID", ""))
    ap.add_argument("--client-secret",
                    default=os.environ.get("GDRIVE_CLIENT_SECRET", ""))
    ap.add_argument("--pair-url", required=True,
                    help="电视配对页显示的二维码内容 / 网址")
    ap.add_argument("--name", default="我的 Google Drive")
    ap.add_argument("--root-folder-id", default="",
                    help="只浏览某个文件夹时填其 ID；留空 = 我的云端硬盘")
    args = ap.parse_args()

    if not args.client_id:
        raise SystemExit("请提供 --client-id 或设置 GDRIVE_CLIENT_ID")

    _Handler.result = None
    _Handler.state = secrets.token_urlsafe(16)
    server = http.server.HTTPServer(("127.0.0.1", PORT), _Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    params = {
        "client_id": args.client_id,
        "redirect_uri": REDIRECT_URI,
        "response_type": "code",
        "scope": SCOPE,
        "access_type": "offline",
        "prompt": "consent",
        "state": _Handler.state,
    }
    url = AUTH_URL + "?" + urllib.parse.urlencode(params)
    print("正在打开浏览器登录 Google…")
    print("若没有自动打开，请手动访问：\n" + url)
    webbrowser.open(url)

    print("等待授权回调（最多 5 分钟）…")
    server.timeout = 300
    while _Handler.result is None:
        server.handle_request()
    server.shutdown()

    result = _Handler.result
    if "code" not in result:
        raise SystemExit("授权未完成")

    print("正在换取 refresh_token…")
    tokens = _exchange(result["code"], args.client_id, args.client_secret)
    refresh = tokens.get("refresh_token")
    if not refresh:
        raise SystemExit(
            "Google 未返回 refresh_token。请确认已加测试用户、"
            "scope 为 drive.readonly、并在授权页重新同意离线访问。"
        )

    payload = {
        "name": args.name,
        "clientId": args.client_id,
        "clientSecret": args.client_secret,
        "refreshToken": refresh,
        "rootFolderId": args.root_folder_id,
    }
    print("正在把凭据提交到电视…")
    try:
        reply = _submit(args.pair_url, payload)
    except urllib.error.URLError as exc:
        raise SystemExit("无法连接电视配对服务：%s" % exc)
    if not reply.get("ok"):
        raise SystemExit("电视拒绝了凭据：%s" % reply.get("error"))
    print("配对成功。请回到电视按「完成」。")


if __name__ == "__main__":
    main()
