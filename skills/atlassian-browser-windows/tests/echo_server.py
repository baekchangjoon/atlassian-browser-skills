#!/usr/bin/env python3
"""Tiny echo server for the Windows transport e2e test (CI only).

GET  /      -> {"ok":true}   (gives Chrome a page on this origin to host fetch())
POST /echo  -> echoes the request body back verbatim

usage: python echo_server.py <port>
"""
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self._send(b'{"ok":true}')

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        self._send(self.rfile.read(n))

    def _send(self, body):
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):  # keep CI logs quiet
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
