#!/usr/bin/env python3
"""atl_playwright.py — same Atlassian REST-in-tab call, but driven by Playwright.

Alternative transport for teams that already standardize on Playwright. Higher
dependency than atl_cdp.* (needs `pip install playwright`), so prefer the CDP
scripts when minimizing dependencies. No `playwright install` browser download
is needed: we ATTACH to the user's Chrome over CDP (connect_over_cdp), reusing
the existing logged-in session.

Prereq: launch Chrome with the debug port (see launch-chrome.ps1 / README):
  chrome --remote-debugging-port=9222 --remote-allow-origins=* \
         --user-data-dir=<dedicated-profile>
then log into Atlassian in that window.

install: pip install playwright     (NO `playwright install` needed)

usage:
  python atl_playwright.py GET  /rest/api/3/myself
  python atl_playwright.py POST /rest/api/3/search/jql '{"jql":"project=ABC"}'

env: ATL_HOST (default "atlassian"), ATL_PORT (9222)
"""
import json
import os
import sys

from playwright.sync_api import sync_playwright

HOST = os.environ.get("ATL_HOST", "atlassian")
PORT = int(os.environ.get("ATL_PORT", "9222"))


def main():
    if len(sys.argv) < 3:
        print(json.dumps({"status": 0, "ok": False,
                          "error": "usage: atl_playwright.py METHOD PATH [BODY_JSON|-]"}))
        sys.exit(2)
    method = sys.argv[1].upper()
    path = sys.argv[2]
    body = sys.argv[3] if len(sys.argv) > 3 else ""
    if body == "-":
        body = sys.stdin.read()
    body_val = None if not body.strip() else json.loads(body)

    with sync_playwright() as p:
        browser = p.chromium.connect_over_cdp(f"http://127.0.0.1:{PORT}")
        page = None
        for ctx in browser.contexts:
            for pg in ctx.pages:
                if HOST in pg.url:
                    page = pg
                    break
            if page:
                break
        if not page:
            print(json.dumps({"status": 0, "ok": False,
                              "error": f"no tab whose URL contains '{HOST}'"}))
            sys.exit(1)

        # Run the same authenticated fetch in the page context.
        result = page.evaluate(
            """async ({method, path, body}) => {
                const opts = { method, credentials: 'include', headers: { 'Accept': 'application/json' } };
                if (body !== null) {
                    opts.headers['Content-Type'] = 'application/json';
                    opts.headers['X-Atlassian-Token'] = 'no-check';
                    opts.body = JSON.stringify(body);
                }
                try {
                    const r = await fetch(location.origin + path, opts);
                    const t = await r.text();
                    let d; try { d = JSON.parse(t); } catch (e) { d = t; }
                    return { status: r.status, ok: r.ok, data: d };
                } catch (e) { return { status: 0, ok: false, error: String(e) }; }
            }""",
            {"method": method, "path": path, "body": body_val},
        )
        print(json.dumps(result))


if __name__ == "__main__":
    main()
