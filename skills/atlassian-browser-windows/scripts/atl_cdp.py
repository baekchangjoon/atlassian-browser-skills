#!/usr/bin/env python3
"""atl_cdp.py — Atlassian REST call inside a Chrome tab via the DevTools Protocol.

Cross-platform alternative to atl_cdp.ps1 for people who already have Python.
Pure standard library: NO pip install (implements a minimal WebSocket client).
Also works on macOS/Linux Chrome, not just Windows.

Prereq: launch Chrome with the debug port (see launch-chrome.ps1 / README), e.g.
  chrome --remote-debugging-port=9222 --remote-allow-origins=* \
         --user-data-dir=<dedicated-profile>
then log into your Atlassian site in that window.

usage:
  python atl_cdp.py GET  /rest/api/3/myself
  python atl_cdp.py POST /rest/api/3/search/jql '{"jql":"project=ABC","maxResults":5}'
  echo '{"jql":"project=ABC"}' | python atl_cdp.py POST /rest/api/3/search/jql -

env: ATL_HOST (default "atlassian"), ATL_PORT (9222), ATL_TIMEOUT_MS (30000)

Prints {"status":..,"ok":..,"data":..} JSON on stdout.
"""
import json
import os
import socket
import struct
import sys
import time
import urllib.request
from base64 import b64encode
from hashlib import sha1

HOST = os.environ.get("ATL_HOST", "atlassian")
PORT = int(os.environ.get("ATL_PORT", "9222"))
TIMEOUT_MS = int(os.environ.get("ATL_TIMEOUT_MS", "30000"))


def fail(msg):
    print(json.dumps({"status": 0, "ok": False, "error": msg}))
    sys.exit(1)


def find_ws_url():
    try:
        raw = urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json", timeout=5).read()
    except Exception as e:  # noqa: BLE001
        fail(f"cannot reach Chrome debug port {PORT} — launch Chrome with "
             f"--remote-debugging-port={PORT}. {e}")
    for t in json.loads(raw):
        if t.get("type") == "page" and HOST in (t.get("url") or ""):
            return t["webSocketDebuggerUrl"]
    fail(f"no Chrome tab whose URL contains '{HOST}' — open your Atlassian site "
         f"in the debug Chrome window first")


# --- minimal RFC6455 client (text frames, single CDP request/response) -------
def ws_connect(url):
    # ws://host:port/path
    assert url.startswith("ws://"), url
    hostport, _, path = url[5:].partition("/")
    host, _, port = hostport.partition(":")
    port = int(port or 80)
    s = socket.create_connection((host, port), timeout=10)
    key = b64encode(os.urandom(16)).decode()
    req = (
        f"GET /{path} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n\r\n"
    )
    s.sendall(req.encode())
    resp = b""
    while b"\r\n\r\n" not in resp:
        chunk = s.recv(4096)
        if not chunk:
            fail("websocket handshake failed (connection closed)")
        resp += chunk
    if b" 101 " not in resp.split(b"\r\n", 1)[0]:
        fail("websocket handshake rejected — launch Chrome with --remote-allow-origins=*")
    return s


def ws_send_text(s, text):
    payload = text.encode("utf-8")
    header = bytearray([0x81])  # FIN + text opcode
    n = len(payload)
    mask = os.urandom(4)
    if n < 126:
        header.append(0x80 | n)
    elif n < 65536:
        header.append(0x80 | 126)
        header += struct.pack(">H", n)
    else:
        header.append(0x80 | 127)
        header += struct.pack(">Q", n)
    header += mask
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    s.sendall(bytes(header) + masked)


def _recv_exact(s, n):
    buf = b""
    while len(buf) < n:
        chunk = s.recv(n - len(buf))
        if not chunk:
            fail("websocket closed while reading")
        buf += chunk
    return buf


def ws_recv_message(s):
    """Read one (possibly fragmented) server message, return its text."""
    data = b""
    while True:
        b0, b1 = _recv_exact(s, 2)
        fin = b0 & 0x80
        length = b1 & 0x7F
        if length == 126:
            length = struct.unpack(">H", _recv_exact(s, 2))[0]
        elif length == 127:
            length = struct.unpack(">Q", _recv_exact(s, 8))[0]
        # server->client frames are never masked
        data += _recv_exact(s, length) if length else b""
        if fin:
            break
    return data.decode("utf-8", "replace")


def main():
    if len(sys.argv) < 3:
        fail("usage: atl_cdp.py METHOD PATH [BODY_JSON|-]")
    method = sys.argv[1].upper()
    path = sys.argv[2]
    body = sys.argv[3] if len(sys.argv) > 3 else ""
    if body == "-":
        body = sys.stdin.read()
    body_js = "null" if not body.strip() else body

    expr = (
        "(async () => {"
        f"  const opts={{method:{json.dumps(method)},credentials:'include',"
        "   headers:{'Accept':'application/json'}};"
        f"  const __b={body_js};"
        "  if(__b!==null){opts.headers['Content-Type']='application/json';"
        "   opts.headers['X-Atlassian-Token']='no-check';opts.body=JSON.stringify(__b);}"
        "  try{"
        f"   const r=await fetch(location.origin+{json.dumps(path)},opts);"
        "    const t=await r.text();let d;try{d=JSON.parse(t)}catch(e){d=t}"
        "    return{status:r.status,ok:r.ok,data:d};"
        "  }catch(e){return{status:0,ok:false,error:String(e)};}"
        "})()"
    )
    msg = json.dumps({
        "id": 1,
        "method": "Runtime.evaluate",
        "params": {"expression": expr, "awaitPromise": True, "returnByValue": True},
    })

    ws_url = find_ws_url()
    s = ws_connect(ws_url)
    s.settimeout(TIMEOUT_MS / 1000.0)
    ws_send_text(s, msg)

    deadline = time.time() + TIMEOUT_MS / 1000.0
    while time.time() < deadline:
        try:
            obj = json.loads(ws_recv_message(s))
        except socket.timeout:
            break
        if obj.get("id") == 1:
            res = obj.get("result", {})
            if "exceptionDetails" in res:
                det = res["exceptionDetails"]
                exc = (det.get("exception") or {}).get("description", "")
                print(json.dumps({"status": 0, "ok": False,
                                  "error": f"JS exception: {det.get('text','')} {exc}"}))
            else:
                print(json.dumps(res.get("result", {}).get("value")))
            try:
                s.close()
            except Exception:  # noqa: BLE001
                pass
            return
    fail(f"timeout after {TIMEOUT_MS}ms waiting for CDP response")


if __name__ == "__main__":
    main()
