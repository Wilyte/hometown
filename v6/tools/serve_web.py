#!/usr/bin/env python3
"""本地起一个静态服务器，预览 dist/web 里的 Godot Web 构建。

    python v6/tools/serve_web.py                    # http://127.0.0.1:5173
    python v6/tools/serve_web.py --port 8000        # 换端口
    python v6/tools/serve_web.py --host 0.0.0.0     # 给局域网里的手机看

默认端口 5173 是部署里 dev 隧道的约定：容器 127.0.0.1:5173 → https://dev.wulie.tech。

几个必须做对的地方：
  · .wasm 用 application/wasm 发，否则浏览器拒绝流式编译（Godot 会退回很慢的路径）。
  · 带 Cross-Origin-Opener-Policy / Cross-Origin-Embedder-Policy，开了
    variant/thread_support 的构建需要它们（默认的 nothreads 构建带不带都能跑）。
  · 不要用 file:// 直接打开 index.html，fetch 不工作。
"""

import argparse
import http.server
import os
import sys

EXTRA_TYPES = {
    ".wasm": "application/wasm",
    ".pck": "application/octet-stream",
    ".js": "text/javascript; charset=utf-8",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, **EXTRA_TYPES}

    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.dirname(os.path.dirname(here))
    ap = argparse.ArgumentParser(description="预览 Godot Web 构建（dist/web）")
    ap.add_argument("--dir", default=os.path.join(repo, "dist", "web"), help="静态文件目录")
    ap.add_argument("--host", default="127.0.0.1", help="监听地址（默认只给本机/dev 隧道）")
    ap.add_argument("--port", type=int, default=5173, help="监听端口（默认 5173）")
    args = ap.parse_args()

    web = os.path.abspath(args.dir)
    index = os.path.join(web, "index.html")
    if not os.path.isfile(index):
        sys.exit("没有 %s\n先出包：pwsh v6/tools/build_web.ps1" % index)

    def make_handler(*a, **kw):
        return Handler(*a, directory=web, **kw)

    with http.server.ThreadingHTTPServer((args.host, args.port), make_handler) as httpd:
        print("serving %s" % web)
        print("  http://%s:%d/" % (args.host, args.port))
        if args.host == "127.0.0.1":
            print("dev 隧道：https://dev.wulie.tech（需 Authelia 登录）")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
