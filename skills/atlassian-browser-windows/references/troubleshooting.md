# Troubleshooting — Windows Chrome DevTools Protocol transport

Error / symptom → cause → fix. The result envelope is always
`{"status":N,"ok":bool,"data"|"error":...}`.

| symptom | cause | fix |
|---------|-------|-----|
| `cannot reach Chrome debug port 9222` | Chrome not launched with the debug port | run `launch-chrome.ps1` (or `chrome.exe --remote-debugging-port=9222 --remote-allow-origins=*`) |
| `websocket connect failed` | launched without `--remote-allow-origins=*` (Chrome ≥111 blocks the DevTools WS) | relaunch with `--remote-allow-origins=*` |
| debug window opens but `/json` lists no page tabs | a normal Chrome with that profile already ran, so the flag was ignored | quit Chrome fully, **or** use a dedicated `--user-data-dir` |
| `no Chrome tab whose URL contains '<host>'` | no matching tab in the debug window | open + log into the site there; self-hosted → `-HostFilter <your-host>` |
| `status:401` / `403` | debug profile not logged in | log into the site once in the debug window (cookies persist in that profile) |
| `status:404` on a valid id/key | Cloud vs DC base-path mismatch | Cloud `/rest/api/3` + `/wiki`; DC `/rest/api/2`, no `/wiki` |
| `400`, `errorMessages: ["Unbounded JQL ..."]` | `search/jql` rejects unrestricted queries | add a restriction, e.g. `project = ABC` |
| `409` on Confluence `PUT` | stale/missing version | `GET ...?expand=version`, send `version.number = current + 1` |
| Confluence page still in trash after `DELETE` | Cloud delete is two-stage | `DELETE /wiki/rest/api/content/<id>?status=trashed` |
| `... cannot be loaded because running scripts is disabled` | PowerShell execution policy | invoke as `powershell -ExecutionPolicy Bypass -File ...` |
| `JS exception: ...` in the result | the in-page `fetch` threw | check the path/Body; confirm the tab origin matches the API |

## Parameters (PowerShell) / env (Python)

| PowerShell | Python env | default | meaning |
|-----------|-----------|---------|---------|
| `-HostFilter` | `ATL_HOST` | `atlassian` | substring matched against tab URLs |
| `-Port` | `ATL_PORT` | `9222` | Chrome remote-debugging port |
| `-TimeoutMs` | `ATL_TIMEOUT_MS` | `30000` | CDP response timeout |

## Why a debug port at all?

Windows has no `osascript`-style bridge into a normally-running Chrome. CDP over
the remote-debugging port is the only supported way to run JS in a logged-in tab
and read the result. The *client*, however, is pure built-in **PowerShell**
(`atl_cdp.ps1`) — it calls `Invoke-RestMethod` on `http://127.0.0.1:<port>/json`
to find the tab, then drives a `System.Net.WebSockets.ClientWebSocket`. No install.
`atl_cdp.py` (pure stdlib) and `atl_playwright.py` (`pip install playwright`) are
optional alternatives.
