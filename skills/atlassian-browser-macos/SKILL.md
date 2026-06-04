---
name: atlassian-browser-macos
description: Use to read or write Jira / Confluence (create / update / delete / comment / transition issues and pages, run JQL/CQL) on macOS when the Atlassian MCP and API tokens are blocked or unavailable. Drives the user's already-logged-in Safari OR Google Chrome tab via osascript and calls Atlassian's own REST API from inside the authenticated browser session — no API token, no MCP.
license: MIT
---

# Atlassian via Safari or Chrome (macOS)

Some environments block the Atlassian MCP and outbound API-token calls.
But the user's **browser** still reaches Jira/Confluence fine (that's how they
use it). This skill runs Atlassian's **own REST API** from *inside* the logged-in
browser tab, so requests carry the existing session cookie (incl. SSO). No token,
no MCP, no extra login.

## How it works

Pick the script for the browser the user is logged into:

| browser | script | applescript |
|---------|--------|-------------|
| Safari  | `scripts/atl_safari.sh`     | `safari_atl.applescript` (`do JavaScript`) |
| Chrome  | `scripts/atl_chrome_mac.sh` | `chrome_atl.applescript` (`execute javascript`) |

Both do the same thing: build a small `fetch()` script, base64-encode it, run it
via `osascript` in the first tab whose URL matches the Atlassian host, then poll
for the async result (neither `do JavaScript` nor `execute javascript` can await a
promise). They use the **live logged-in session** — no debug port, no separate
profile, no relaunch. You only choose the **METHOD + PATH + BODY**; see
`references/atlassian-rest-cookbook.md` (repo root) for every endpoint and payload.

## One-time setup (REQUIRED — walk the user through this)

Both browsers block AppleScript-driven JS until the user explicitly opts in.
Until they do, every call returns an `inject failed: ... Allow JavaScript from
Apple Events ...` error. If you see that, stop and have the user do the steps for
their browser, then **log into the Atlassian site** (`https://<site>.atlassian.net`
or the self-hosted host) and **leave that tab open**.

### Safari
1. **Show the Develop menu.** Safari ▸ Settings… (⌘,) ▸ **Advanced** tab ▸ check
   **"Show features for web developers"** (older macOS: "Show Develop menu in menu bar").
   - 한글: Safari ▸ 설정… ▸ **고급** ▸ **"웹 개발자용 기능 보기"** 체크
2. **Allow Apple Events JS.** Menu bar **Develop** ▸ check
   **"Allow JavaScript from Apple Events"**.
   - 한글: 메뉴 막대 **개발자용** ▸ **"Apple Events의 JavaScript 허용"** 체크

### Google Chrome
1. **Allow Apple Events JS.** Menu bar **View ▸ Developer** ▸ check
   **"Allow JavaScript from Apple Events"**. (Chrome's `execute javascript` is the
   twin of Safari's `do JavaScript`; this single toggle is the only Chrome-side step.)
   - 한글: 메뉴 막대 **보기 ▸ 개발자용** ▸ **"Apple Events의 JavaScript 허용"** 체크

### Both
3. **Approve Automation** (first run only). When a script first talks to the
   browser, macOS shows a permission prompt — click **OK/허용**. If you missed it:
   System Settings ▸ Privacy & Security ▸ **Automation** ▸ enable your
   terminal/agent → **Safari** / **Google Chrome**.
   - 한글: 시스템 설정 ▸ 개인정보 보호 및 보안 ▸ **자동화** ▸ 터미널/에이전트 → 해당 브라우저 켜기

Verify with a harmless read — it should return `"status":200`:
```bash
# Safari:
skills/atlassian-browser-macos/scripts/atl_safari.sh    GET /rest/api/3/myself
# Chrome:
skills/atlassian-browser-macos/scripts/atl_chrome_mac.sh GET /rest/api/3/myself
```

## Usage

```bash
# Safari → atl_safari.sh ; Chrome → atl_chrome_mac.sh (identical interface)
SH=skills/atlassian-browser-macos/scripts/atl_safari.sh

# read
"$SH" GET  /rest/api/3/myself
"$SH" GET  "/rest/api/3/issue/ABC-123?fields=summary,status,assignee"

# search (JQL)
"$SH" POST /rest/api/3/search/jql '{"jql":"project = ABC AND statusCategory != Done","maxResults":20,"fields":["summary","status"]}'

# create issue (Cloud uses ADF for description)
"$SH" POST /rest/api/3/issue '{"fields":{"project":{"key":"ABC"},"issuetype":{"name":"Task"},"summary":"Hello"}}'

# update / comment / transition / delete
"$SH" PUT    /rest/api/3/issue/ABC-123 '{"fields":{"summary":"New title"}}'
"$SH" POST   /rest/api/3/issue/ABC-123/comment '{"body":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"hi"}]}]}}'
"$SH" DELETE /rest/api/3/issue/ABC-123

# Confluence (Cloud is under /wiki)
"$SH" GET  "/wiki/rest/api/content/123456?expand=body.storage,version"
"$SH" POST /wiki/rest/api/content '{"type":"page","title":"New","space":{"key":"DOCS"},"body":{"storage":{"value":"<p>hi</p>","representation":"storage"}}}'
```

Big/awkward bodies: pipe via stdin with `-` as the body arg:
```bash
echo '{"jql":"project = ABC"}' | "$SH" POST /rest/api/3/search/jql -
```

Self-hosted (Server/DC) host: set `ATL_HOST` to a substring of its URL, and use
`/rest/api/2` (Jira) / `/rest/api` (Confluence):
```bash
ATL_HOST=jira.company.com "$SH" GET /rest/api/2/myself
```

## Output

Always JSON: `{"status":200,"ok":true,"data":{...}}`. Parse it yourself.
- `ok:false` + `401/403` → not logged in / wrong tab.
- `404` → Cloud vs DC base-path mismatch, or bad id/key.
- `"Safari is not running"` / `"Google Chrome is not running"` / `"no tab whose URL contains ..."` → open & log into the site first.

### Parsing the output safely

Save the response to a file, then parse it with a **quoted heredoc** (`'PYEOF'`)
so the shell never touches the Python code — no `\"` escaping needed:

```bash
"$SH" GET /rest/api/3/myself > /tmp/atl_resp.json

python3 - /tmp/atl_resp.json <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
print(f"{d['status']}\t{d['ok']}")
PYEOF
```

Never pipe into `python3 -c '...'` with `\"`-escaped quotes: inside shell single
quotes the backslashes reach Python verbatim and fail with
`SyntaxError: unexpected character after line continuation character`.
Inside a `'PYEOF'` heredoc shell variables do **not** expand — pass values in
via `sys.argv` or env instead. For simple field extraction, `jq -r '.data.key'`
is an even shorter alternative.

## Rules

- **Read freely.** Reads (`GET`, JQL/CQL search) need no approval.
- **Confirm writes.** Before any `POST`/`PUT`/`DELETE` that creates, edits,
  deletes, comments, or transitions, state the exact target and get user approval
  (per the workspace's external-write policy). Never bulk-delete without explicit
  confirmation.
- Prefer this only when MCP/API are actually unavailable; if the Atlassian MCP or
  a sanctioned API path exists, use that instead.

## Examples

Concrete input → output (Jira Cloud; `SH` = `atl_safari.sh` or `atl_chrome_mac.sh`).

**Read the current user**
```console
$ skills/atlassian-browser-macos/scripts/atl_safari.sh GET /rest/api/3/myself
{"status":200,"ok":true,"data":{"accountId":"5b10...","emailAddress":"you@corp.com"}}
```

**Create an issue, then delete it (self-clean demo)**
```console
$ "$SH" POST /rest/api/3/issue '{"fields":{"project":{"key":"ABC"},"issuetype":{"name":"Task"},"summary":"demo"}}'
{"status":201,"ok":true,"data":{"id":"10110","key":"ABC-42"}}
$ "$SH" DELETE /rest/api/3/issue/ABC-42
{"status":204,"ok":true,"data":""}
```

**Search with JQL (bounded query required)**
```console
$ "$SH" POST /rest/api/3/search/jql '{"jql":"project = ABC ORDER BY created DESC","maxResults":3,"fields":["summary"]}'
{"status":200,"ok":true,"data":{"issues":[{"key":"ABC-7","fields":{"summary":"..."}}]}}
```

## Decision rules (IF → THEN)

- **IF** a call returns `inject failed: ... Allow JavaScript from Apple Events`
  **THEN** the one-time toggle is off — stop and do the setup steps; do **not** retry blindly.
- **IF** `status` is `401`/`403` **THEN** the tab isn't logged in (or it's the wrong
  tab) — have the user log into the site, then retry.
- **IF** `status` is `404` on a valid id **THEN** the base path is wrong — switch
  Cloud `/rest/api/3` ↔ DC `/rest/api/2` (and `/wiki` for Confluence Cloud).
- **IF** the host is `*.atlassian.net` **THEN** use Cloud paths (ADF bodies, `/wiki`
  for Confluence); **ELSE** assume Server/DC (plain-text bodies, no `/wiki`).
- **IF** JQL search returns `400 Unbounded JQL` **THEN** add a restriction
  (e.g. `project = ABC`) — `search/jql` rejects unrestricted queries.
- **IF** the action is a write (`POST`/`PUT`/`DELETE`) **THEN** state the target and
  get approval before running.

## Anti-patterns & pitfalls

- **Don't scrape the DOM.** Call the REST API via `fetch` — DOM selectors break on
  every Atlassian UI change.
- **Don't add an `Authorization` header.** The session cookie already authenticates
  the same-origin request; an injected token would be wrong and may be blocked.
- **Don't poll-retry the `Allow JavaScript from Apple Events` error** — it never
  succeeds until the user flips the toggle.
- **Don't forget the version bump** on Confluence updates: a `PUT` without
  `version.number = current + 1` fails with `409`.
- **Don't assume Confluence `DELETE` purges** — it trashes first; purge with
  `?status=trashed`.
- **Don't reuse another issue's transition ids** — always `GET …/transitions`
  first; ids differ per workflow.
- **Don't parse the output with `\"`-escaped inline `python3 -c`** — use the
  file + `'PYEOF'` heredoc pattern from [Output](#output).

## Testing

Automated, CI-safe checks (bash syntax, AppleScript compile, arg validation,
generated-JS validity — no browser/Automation needed):
```bash
bash skills/atlassian-browser-macos/tests/test_macos.sh
```
Run in CI by [`.github/workflows/test-atlassian-browser-macos.yml`](../../.github/workflows/test-atlassian-browser-macos.yml)
on every PR to `main` and on merge.

Manual checks against a live tab:
```bash
# 1) plumbing only — expect a clean error, NO external call:
ATL_HOST=__none__ scripts/atl_safari.sh GET /rest/api/3/myself
#    → {"status":0,"ok":false,"error":"no tab whose URL contains '__none__' ..."}

# 2) with a logged-in tab open — expect "status":200:
scripts/atl_safari.sh    GET /rest/api/3/myself
scripts/atl_chrome_mac.sh GET /rest/api/3/myself

# 3) full self-clean CRUD (writes — get approval first):
#    create → read → update → comment → transition → delete, then GET → expect 404.

# syntax checks:
bash -n scripts/atl_safari.sh scripts/atl_chrome_mac.sh
osacompile -o /tmp/_t.scpt scripts/safari_atl.applescript && rm /tmp/_t.scpt
osacompile -o /tmp/_t.scpt scripts/chrome_atl.applescript && rm /tmp/_t.scpt
```

## Changelog

- **1.1.0** — add Google Chrome transport (`atl_chrome_mac.sh` +
  `chrome_atl.applescript`) alongside Safari; both use the live logged-in session.
  Document safe output parsing (save to file + quoted `'PYEOF'` heredoc).
- **1.0.0** — initial Safari transport via osascript + REST cookbook.

## References

- [`references/troubleshooting.md`](references/troubleshooting.md) — error → cause →
  fix table for this skill.
- [`../../references/atlassian-rest-cookbook.md`](../../references/atlassian-rest-cookbook.md)
  — full Jira/Confluence endpoint + payload reference (Cloud & DC).
