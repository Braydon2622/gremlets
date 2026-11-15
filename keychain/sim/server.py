#!/usr/bin/env python3
"""Keychain simulator server.

Serves the repo (so the sim can load Species/<id>/sheet.png) and proxies /api/status to the Gremlets app's
local API, so the simulated keychain can show real Claude updates. Local only (127.0.0.1).

Run from anywhere:  python3 keychain/sim/server.py   then open http://127.0.0.1:8770/keychain/sim/
"""
import http.server, os, urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
APP = "http://127.0.0.1:" + os.environ.get("GREMLETS_PORT", "47920")
PORT = int(os.environ.get("SIM_PORT", "8770"))


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=ROOT, **k)

    def do_GET(self):
        if self.path.startswith("/api/status"):
            try:
                req = urllib.request.Request(APP + "/status", method="POST", headers={"X-Gremlets": "1"})
                body = urllib.request.urlopen(req, timeout=1.5).read()
                self._send(200, body)
            except Exception:
                self._send(503, b'{"ok":false,"error":"Gremlets app not running"}')
            return
        super().do_GET()

    def _send(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    print(f"Keychain sim: http://127.0.0.1:{PORT}/keychain/sim/")
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
