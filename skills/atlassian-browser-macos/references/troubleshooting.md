# Troubleshooting — macOS Safari / Chrome transport

Error / symptom → cause → fix. The result envelope is always
`{"status":N,"ok":bool,"data"|"error":...}`.

| symptom | cause | fix |
|---------|-------|-----|
| `inject failed: ... Allow JavaScript from Apple Events` | one-time browser toggle is off | Safari: Develop ▸ **Allow JavaScript from Apple Events**. Chrome: View ▸ Developer ▸ **Allow JavaScript from Apple Events**. |
| `"Safari is not running"` / `"Google Chrome is not running"` | the target browser isn't open | launch it and open the Atlassian site |
| `"no tab whose URL contains '<host>'"` | no open tab matches the host filter | open + log into the site; for self-hosted set `ATL_HOST=<your-host>` |
| first call hangs, then a macOS prompt appears | Automation permission not yet granted | click **OK**, or System Settings ▸ Privacy & Security ▸ **Automation** ▸ terminal → browser |
| `status:401` / `403` | tab not logged in, or wrong tab matched | log into the site in that tab; narrow `ATL_HOST` |
| `status:404` on a valid id/key | Cloud vs DC base-path mismatch | Cloud `/rest/api/3` + `/wiki`; DC `/rest/api/2`, no `/wiki` |
| `status:400`, `data.errorMessages: ["Unbounded JQL ..."]` | `search/jql` rejects unrestricted queries | add a restriction, e.g. `project = ABC` |
| `status:409` on Confluence `PUT` | stale/missing version number | `GET ...?expand=version`, then send `version.number = current + 1` |
| Confluence page still in trash after `DELETE` | Cloud delete is two-stage | second call: `DELETE /wiki/rest/api/content/<id>?status=trashed` |
| `status:0`, `error` contains `Failed to fetch` | network blocked, or wrong origin tab | run from a tab actually on the target site |
| timeout after N ms | page busy or fetch never resolved | raise `ATL_TIMEOUT_MS`; confirm the tab is responsive |

## Environment knobs

| var | default | meaning |
|-----|---------|---------|
| `ATL_HOST` | `atlassian` | substring matched against tab URLs to pick the target tab |
| `ATL_TIMEOUT_MS` | `30000` | poll timeout for the async fetch result |

## Notes

- `do JavaScript` (Safari) and `execute javascript` (Chrome) both return
  synchronously and **cannot await a promise**, so the wrapper stashes the fetch
  result on `window.__ATL_RESULT` / `window.__ATL_DONE` and the AppleScript side
  polls. This is expected, not a bug.
- The injected payload is base64-encoded only to survive AppleScript string
  escaping; it is our own code, not external input.
