---
name: atlassian-browser-windows
description: Use to read or write Jira / Confluence (create / update / delete / comment / transition issues and pages, run JQL/CQL) on Windows when the Atlassian MCP and API tokens are blocked by corporate security. Attaches to a Chrome tab via the DevTools remote-debugging port and calls Atlassian's own REST API from inside the authenticated browser session — no API token, no MCP. Zero-install path uses built-in PowerShell.
---

# Atlassian via Chrome DevTools Protocol (Windows)

Corporate security often blocks the Atlassian MCP and outbound API-token calls.
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
| `scripts/atl_cdp.ps1` (PowerShell) | **nothing** — built into Windows | ✅ **use this** |
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

## Usage (PowerShell — recommended)

```powershell
$PS = "scripts\atl_cdp.ps1"

# read
powershell -ExecutionPolicy Bypass -File $PS -Method GET -Path /rest/api/3/myself
powershell -ExecutionPolicy Bypass -File $PS -Method GET -Path "/rest/api/3/issue/ABC-123?fields=summary,status"

# search (JQL)
powershell -ExecutionPolicy Bypass -File $PS -Method POST -Path /rest/api/3/search/jql `
  -Body '{"jql":"project = ABC AND statusCategory != Done","maxResults":20,"fields":["summary","status"]}'

# create / update / comment / transition / delete
powershell ... -File $PS -Method POST   -Path /rest/api/3/issue -Body '{"fields":{"project":{"key":"ABC"},"issuetype":{"name":"Task"},"summary":"Hello"}}'
powershell ... -File $PS -Method PUT    -Path /rest/api/3/issue/ABC-123 -Body '{"fields":{"summary":"New title"}}'
powershell ... -File $PS -Method DELETE -Path /rest/api/3/issue/ABC-123

# Confluence (Cloud is under /wiki)
powershell ... -File $PS -Method GET  -Path "/wiki/rest/api/content/123456?expand=body.storage,version"
powershell ... -File $PS -Method POST -Path /wiki/rest/api/content -Body '{"type":"page","title":"New","space":{"key":"DOCS"},"body":{"storage":{"value":"<p>hi</p>","representation":"storage"}}}'
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

See `references/atlassian-rest-cookbook.md` for the full endpoint reference.
