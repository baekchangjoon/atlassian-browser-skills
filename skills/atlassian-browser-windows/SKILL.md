---
name: atlassian-browser-windows
description: Use to read or write Jira / Confluence (create / update / delete / comment / transition issues and pages, run JQL/CQL) on Windows when the Atlassian MCP and API tokens are blocked or unavailable. Attaches to a Chrome tab via the DevTools remote-debugging port and calls Atlassian's own REST API from inside the authenticated browser session — no API token, no MCP. Zero-install path uses built-in PowerShell.
license: MIT
---

# Atlassian via Chrome DevTools Protocol (Windows)

Some environments block the Atlassian MCP and outbound API-token calls.
But the user's **browser** still reaches Jira/Confluence (that's how they use it).
This skill attaches to Chrome over the **DevTools remote-debugging port** and runs
Atlassian's **own REST API** from inside the logged-in tab, so requests carry the
existing session cookie (incl. SSO). No token, no MCP.

You only choose **METHOD + PATH + BODY**; see
`references/atlassian-rest-cookbook.md` (repo root) for every endpoint/payload.

## Is there an "osascript for Chrome" on Windows? (short answer: no — use PowerShell)

On macOS, `osascript` drives the *already-running* Safari/Chrome with no relaunch.
**Windows has no such bridge** — Chrome on Windows exposes no scripting interface
to a normally-launched browser. The only supported way to run JS in a logged-in
Chrome tab and read the result back is the **DevTools Protocol (CDP)** over the
remote-debugging port. (Old IE COM automation is gone; `javascript:` in the
address bar is blocked; extracting cookies to call the API from outside the
browser would be both fragile *and* hit the firewall you're trying to avoid.)

So CDP is unavoidable — **but you do NOT need Python or any install.** The CDP
*client* can be **pure Windows PowerShell, which is preinstalled** (it opens the
WebSocket itself). That is the lightweight, built-in counterpart to osascript.
Python/Playwright are optional extras, not requirements.

| client | install | when |
|--------|---------|------|
| `scripts/atl_cdp.ps1` (PowerShell) | **nothing** — works on PS 5.1 (`powershell`) and PS 7+ (`pwsh`) | ✅ **use this** |
| `scripts/atl_cdp.py` | Python only (pure stdlib, no pip) | optional — only if you'd rather script in Python |
| `scripts/atl_playwright.py` | `pip install playwright` | optional — only if already standardized on Playwright |

All three do the same thing (attach over CDP → authenticated `fetch` in the tab →
return `{status,ok,data}` JSON).

The one unavoidable difference vs macOS: you must **start Chrome once with the
debug-port flag** (next section). There is no way around this on Windows.

## One-time setup (tell the user)

1. Launch Chrome with the debug port using a **dedicated profile** (so it doesn't
   disturb their main Chrome, and the flag is actually honored):
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\launch-chrome.ps1
   ```
   (Or manually: `chrome.exe --remote-debugging-port=9222 --remote-allow-origins=* --user-data-dir="%LOCALAPPDATA%\atl-cdp-profile"`.)
   Edge works too — `launch-chrome.ps1` falls back to it.
2. **Log into** the Atlassian site in that window (first time only; cookies
   persist in the dedicated profile).

> `--remote-allow-origins=*` is required (Chrome ≥111 rejects the DevTools
> WebSocket otherwise). The dedicated `--user-data-dir` is required because Chrome
> ignores `--remote-debugging-port` when an instance with that profile is already
> running.

**Avoid the one-time re-login (optional):** to reuse the user's *existing* Chrome
login instead of a fresh profile, fully **quit Chrome** first, then relaunch with
the flag on the normal profile (omit `--user-data-dir`):
`chrome.exe --remote-debugging-port=9222 --remote-allow-origins=*`. Existing
cookies/SSO carry over, so no new login — the trade-off is you must quit and
relaunch your main Chrome. The dedicated-profile route above doesn't disturb your
main Chrome but needs one login.

## Picking the site (ask — don't guess)

The clients find the target tab by URL substring (`ATL_HOST` / `-HostFilter`,
default `atlassian`). Cloud (`https://<site>.atlassian.net`) matches the default —
no address needed as long as a logged-in tab is open in the debug window.
Self-hosted (Server/DC) requires the host filter set to their hostname — if the
user hasn't given the address, **ask for it**; never guess a hostname.

To discover or confirm candidates, list the debug window's tabs (read-only):

```powershell
Invoke-RestMethod http://127.0.0.1:9222/json | Select-Object type, url
```

If several Atlassian-looking tabs match (e.g. two sites), show them and ask the
user which one to use, then set the host filter to that hostname.

## Usage (PowerShell — recommended)

Works on both **PowerShell 5.1** (`powershell`) and **PowerShell 7+** (`pwsh`).
Use whichever is available; substitute `pwsh` for `powershell` if preferred.

```powershell
$PS = "scripts\atl_cdp.ps1"

# read
powershell -ExecutionPolicy Bypass -File $PS -Method GET -Path /rest/api/3/myself
powershell -ExecutionPolicy Bypass -File $PS -Method GET -Path "/rest/api/3/issue/ABC-123?fields=summary,status"

# search (JQL)
powershell -ExecutionPolicy Bypass -File $PS -Method POST -Path /rest/api/3/search/jql `
  -Body '{"jql":"project = ABC AND statusCategory != Done","maxResults":20,"fields":["summary","status"]}'

# create / update / comment / transition / delete
powershell -ExecutionPolicy Bypass -File $PS -Method POST   -Path /rest/api/3/issue -Body '{"fields":{"project":{"key":"ABC"},"issuetype":{"name":"Task"},"summary":"Hello"}}'
powershell -ExecutionPolicy Bypass -File $PS -Method PUT    -Path /rest/api/3/issue/ABC-123 -Body '{"fields":{"summary":"New title"}}'
powershell -ExecutionPolicy Bypass -File $PS -Method DELETE -Path /rest/api/3/issue/ABC-123

# Confluence (Cloud is under /wiki)
powershell -ExecutionPolicy Bypass -File $PS -Method GET  -Path "/wiki/rest/api/content/123456?expand=body.storage,version"
powershell -ExecutionPolicy Bypass -File $PS -Method POST -Path /wiki/rest/api/content -Body '{"type":"page","title":"New","space":{"key":"DOCS"},"body":{"storage":{"value":"<p>hi</p>","representation":"storage"}}}'
```

## Usage (Python stdlib alternative)

```bash
python scripts\atl_cdp.py GET  /rest/api/3/myself
python scripts\atl_cdp.py POST /rest/api/3/search/jql '{"jql":"project=ABC","maxResults":5}'
echo {"jql":"project=ABC"} | python scripts\atl_cdp.py POST /rest/api/3/search/jql -
```

Options via env: `ATL_HOST` (tab URL match, default `atlassian`), `ATL_PORT`
(9222), `ATL_TIMEOUT_MS` (30000). PowerShell uses `-HostFilter` / `-Port` /
`-TimeoutMs`. For self-hosted Server/DC, set the host filter to its hostname and
use `/rest/api/2` (Jira) / `/rest/api` (Confluence).

## Output

Always JSON: `{"status":200,"ok":true,"data":{...}}`. Parse it yourself.
- `ok:false` + `401/403` → not logged in / wrong tab.
- `404` → Cloud vs DC base-path mismatch, or bad id/key.
- `cannot reach Chrome debug port` → run `launch-chrome.ps1` first.
- `no Chrome tab whose URL contains ...` → open & log into the site in the debug window.
- `websocket connect failed` → relaunch Chrome with `--remote-allow-origins=*`.

## Rules

- **Read freely.** Reads (`GET`, JQL/CQL search) need no approval.
- **Confirm writes.** Before any `POST`/`PUT`/`DELETE` that creates, edits,
  deletes, comments, or transitions, state the exact target and get user approval.
  Never bulk-delete without explicit confirmation.
- Prefer this only when MCP/API are actually unavailable.

## Examples

Concrete input → output (Jira Cloud). Tools used: `powershell`, `chrome.exe`,
`launch-chrome.ps1`, `atl_cdp.ps1` (which calls `Invoke-RestMethod` on
`http://127.0.0.1:9222/json` and opens a `System.Net.WebSockets.ClientWebSocket`).

**Start Chrome on the debug port, then read the current user**
```console
PS> powershell -ExecutionPolicy Bypass -File scripts\launch-chrome.ps1
PS> powershell -ExecutionPolicy Bypass -File scripts\atl_cdp.ps1 -Method GET -Path /rest/api/3/myself
{"status":200,"ok":true,"data":{"accountId":"5b10...","emailAddress":"you@corp.com"}}
```

**Create an issue, then delete it (self-clean demo)**
```console
PS> powershell -File scripts\atl_cdp.ps1 -Method POST -Path /rest/api/3/issue -Body '{"fields":{"project":{"key":"ABC"},"issuetype":{"name":"Task"},"summary":"demo"}}'
{"status":201,"ok":true,"data":{"id":"10110","key":"ABC-42"}}
PS> powershell -File scripts\atl_cdp.ps1 -Method DELETE -Path /rest/api/3/issue/ABC-42
{"status":204,"ok":true,"data":""}
```

**Same call, Python alternative (no pip):**
```console
> python scripts\atl_cdp.py GET /rest/api/3/myself
{"status":200,"ok":true,"data":{"accountId":"5b10..."}}
```

## Decision rules (IF → THEN)

- **IF** the site is self-hosted and you don't have its address **THEN** ask the
  user (optionally listing the debug window's tab URLs to offer candidates) —
  never guess a hostname or fire blind calls.
- **IF** `atl_cdp.ps1` prints `cannot reach Chrome debug port` **THEN** Chrome
  isn't on the port — run `launch-chrome.ps1` first; do **not** retry blindly.
- **IF** you get `websocket connect failed` **THEN** Chrome was launched without
  `--remote-allow-origins=*` (Chrome ≥111 rejects the DevTools WebSocket) — relaunch with it.
- **IF** `launch-chrome.ps1` opens a window but the port has no tabs **THEN** an
  existing Chrome with that profile swallowed the flag — quit Chrome fully, or use
  the dedicated `--user-data-dir` profile.
- **IF** `status` is `401`/`403` **THEN** the debug window isn't logged in — log
  into the site there once (cookies persist in the profile), then retry.
- **IF** `status` is `404` on a valid id **THEN** switch Cloud `/rest/api/3` ↔ DC
  `/rest/api/2` (and `/wiki` for Confluence Cloud).
- **IF** the host is `*.atlassian.net` **THEN** use Cloud paths (ADF bodies,
  `/wiki` for Confluence); **ELSE** assume Server/DC.
- **IF** JQL returns `400 Unbounded JQL` **THEN** add a restriction like `project = ABC`.
- **IF** the action is a write (`POST`/`PUT`/`DELETE`) **THEN** state the target and
  get approval before running.

## Anti-patterns & pitfalls

- **Don't launch the debug port on your *main* profile while Chrome is running** —
  the flag is silently ignored. Use a dedicated `--user-data-dir`, or quit first.
- **Don't omit `--remote-allow-origins=*`** — the WebSocket upgrade is rejected.
- **Don't reach for Python or Playwright by default** — `atl_cdp.ps1` (built-in
  PowerShell) needs nothing installed; the others are optional.
- **Don't scrape the DOM** — call the REST API via in-page `fetch`.
- **Don't add an `Authorization` header** — the session cookie authenticates the
  same-origin request.
- **Don't forget the Confluence version bump** (`PUT` needs `version.number = current + 1`)
  and that `DELETE` only trashes (purge with `?status=trashed`).
- **Don't re-encode non-ASCII (e.g. Korean) bodies yourself** — the transport is
  UTF-8 safe end-to-end; pass the JSON body as-is.
- **Don't rebuild a whole ADF document to change one part** — `GET` the current
  body, keep the original nodes untouched, and construct only the replacement
  nodes (tables and complex formatting are easy to corrupt otherwise).
- **Don't trust a write containing non-ASCII text blindly** — `GET` the
  issue/page back once and confirm the text round-tripped without mojibake.

## Testing

Automated, CI-safe checks (parse, no-Chrome error path, parameter validation —
no browser/debug port needed), run under both PowerShell hosts:
```powershell
powershell -ExecutionPolicy Bypass -File skills\atlassian-browser-windows\tests\test_windows.ps1 -PsHost powershell
pwsh       -ExecutionPolicy Bypass -File skills\atlassian-browser-windows\tests\test_windows.ps1 -PsHost pwsh
```
Run in CI by [`.github/workflows/test-atlassian-browser-windows.yml`](../../.github/workflows/test-atlassian-browser-windows.yml)
(PS 5.1 + 7 matrix) on every PR to `main` and on merge. CI additionally runs a
UTF-8 e2e round-trip (`tests/test_windows_e2e.ps1`) against a real headless
Chrome + local echo server — Korean bodies, including >64KB — no Atlassian needed.

Manual checks against a live tab:
```powershell
# 1) is the debug port up? (run before anything else)
Invoke-RestMethod http://127.0.0.1:9222/json | Select-Object type, url
#    from any shell you can instead use:  curl http://127.0.0.1:9222/json

# 2) plumbing only — expect a clean error, NO external call:
powershell -File scripts\atl_cdp.ps1 -Method GET -Path /rest/api/3/myself -HostFilter __none__
#    → {"status":0,"ok":false,"error":"no Chrome tab whose URL contains '__none__' ..."}

# 3) with a logged-in debug tab — expect "status":200:
powershell -File scripts\atl_cdp.ps1 -Method GET -Path /rest/api/3/myself

# 4) full self-clean CRUD (writes — get approval first):
#    create → read → update → comment → transition → delete, then GET → expect 404.
```
```bash
# syntax-check the Python client (cross-checks the shared JS payload too):
python -m py_compile scripts/atl_cdp.py scripts/atl_playwright.py
```

## Changelog

- **1.2.0** — UTF-8 hardening: decode WebSocket frames once from accumulated
  bytes in `atl_cdp.ps1` (per-chunk decoding corrupted multibyte chars split
  across 64KB reads); add a CI e2e UTF-8 round-trip test against real Chrome;
  add non-ASCII/ADF anti-patterns.
- **1.1.0** — "ask, don't guess" flow: establish the site by asking the user
  (with read-only debug-tab listing to offer candidates) before the first call.
- **1.0.0** — Chrome DevTools Protocol transport: PowerShell client (`atl_cdp.ps1`,
  zero-install), pure-stdlib Python client (`atl_cdp.py`), Playwright client
  (`atl_playwright.py`), and `launch-chrome.ps1` helper.

## References

- [`references/troubleshooting.md`](references/troubleshooting.md) — error → cause →
  fix table for this skill.
- [`../../references/atlassian-rest-cookbook.md`](../../references/atlassian-rest-cookbook.md)
  — full Jira/Confluence endpoint + payload reference (Cloud & DC).
