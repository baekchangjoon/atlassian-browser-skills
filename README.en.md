# atlassian-browser-skills

> 🌐 [한국어](README.md) · **English** (this page)

Read/write **Jira & Confluence** from an LLM agent **when the Atlassian MCP and
API tokens are blocked** by corporate security — by driving the user's own
already-logged-in **local browser** (Safari/Chrome/Edge). No API token, no MCP.

## The idea

The corporate firewall blocks *external* access paths (the Atlassian MCP,
personal API tokens). It does **not** block the browser the user already uses to
open Jira/Confluence. So instead of an external API client, we execute a
**same-origin `fetch()` inside the authenticated browser tab**, calling
Atlassian's *own* REST API — the very endpoints the Jira/Confluence SPA uses.

```
LLM agent
  └─ skill (METHOD + PATH + BODY, chosen from the REST cookbook)
       └─ transport: run JS in the logged-in tab
            ├─ macOS:   osascript → Safari / Chrome  (do JavaScript / execute javascript)
            └─ Windows: PowerShell/Python → Chrome DevTools Protocol (Runtime.evaluate)
                 └─ fetch(location.origin + PATH)  ← carries session cookie / SSO
                      └─ Atlassian REST API  →  CRUD on issues & pages
```

Benefits: **no API token, no MCP, no extra login**, and because we call the REST
API (not scrape the DOM) the result is structured and stable.

## Layout

```
references/atlassian-rest-cookbook.md      # shared: every endpoint + payload (Jira/Confluence, Cloud & DC)
skills/
  atlassian-browser-macos/                 # Safari OR Chrome, via osascript (live session)
    SKILL.md
    scripts/atl_safari.sh                   #   Safari wrapper: build fetch JS, run via osascript, poll
    scripts/safari_atl.applescript          #     find tab + do JavaScript + poll
    scripts/atl_chrome_mac.sh               #   Chrome wrapper (identical interface)
    scripts/chrome_atl.applescript          #     find tab + execute javascript + poll
  atlassian-browser-windows/               # Chrome DevTools Protocol
    SKILL.md
    scripts/atl_cdp.ps1                      #   RECOMMENDED — zero install (built-in PowerShell)
    scripts/atl_cdp.py                       #   optional alt — pure stdlib Python (no pip)
    scripts/atl_playwright.py                #   alt — Playwright (pip), attach over CDP
    scripts/launch-chrome.ps1               #   launch Chrome/Edge with the debug port
```

## Windows: why PowerShell-CDP is the recommended path

The brief asked for the **lowest-dependency, most-accessible** Windows option.

| option | install footprint | notes |
|--------|-------------------|-------|
| **CDP via PowerShell** (`atl_cdp.ps1`) | **nothing** — PS 5.1 + Chrome are already on every corporate Windows | ✅ recommended |
| CDP via Python (`atl_cdp.py`) | Python only, **no pip** (stdlib WebSocket) | optional — only if you'd rather script in Python |
| Playwright (`atl_playwright.py`) | `pip install playwright` | heaviest; only if already standardized on it |

Unlike macOS, Windows has **no `osascript`-style bridge** into a normally-running
Chrome — CDP over the debug port is the only way to reach the logged-in tab. But
the CDP *client* is **pure built-in PowerShell**, so there's still nothing to
install: PowerShell is the lightweight, osascript-equivalent answer here. **You do
not need Python** — `atl_cdp.py` and `atl_playwright.py` are optional extras only.
The single unavoidable step vs macOS is launching Chrome once with the debug-port
flag.

> All Windows transports **attach** to Chrome over CDP — they reuse the user's
> existing login, so there's no `playwright install` browser download.

## Quick start

**macOS (Safari)** — one-time setup, then a read:
1. **Show Develop menu:** Safari ▸ Settings… (⌘,) ▸ **Advanced** ▸ check
   **"Show features for web developers"**.
   (한글: 설정 ▸ **고급** ▸ **"웹 개발자용 기능 보기"**)
2. **Allow Apple Events JS:** menu bar **Develop** ▸ check
   **"Allow JavaScript from Apple Events"**.
   (한글: **개발자용** ▸ **"Apple Events의 JavaScript 허용"**)
3. **Approve Automation** when first prompted (or System Settings ▸ Privacy &
   Security ▸ **Automation** ▸ your terminal → **Safari**).
4. **Log into** the Atlassian site in a Safari tab and leave it open.
5. Run: `skills/atlassian-browser-macos/scripts/atl_safari.sh GET /rest/api/3/myself`
   → expect `"status":200`.

**macOS (Google Chrome)** — same idea, one toggle, uses the live logged-in Chrome
(no debug port / no separate profile):
1. **Allow Apple Events JS:** menu bar **View ▸ Developer** ▸ check
   **"Allow JavaScript from Apple Events"**. (한글: **보기 ▸ 개발자용** ▸ **"Apple Events의 JavaScript 허용"**)
2. **Approve Automation** when first prompted (System Settings ▸ Privacy & Security ▸
   **Automation** ▸ your terminal → **Google Chrome**).
3. **Log into** the Atlassian site in a Chrome tab and leave it open.
4. Run: `skills/atlassian-browser-macos/scripts/atl_chrome_mac.sh GET /rest/api/3/myself`
   → expect `"status":200`.

> Without the toggle every call returns
> `{"status":0,"ok":false,"error":"inject failed: ... Allow JavaScript from Apple Events ..."}`.
> Full details: [`skills/atlassian-browser-macos/SKILL.md`](skills/atlassian-browser-macos/SKILL.md).

**Windows (Chrome):**
1. `powershell -ExecutionPolicy Bypass -File skills\atlassian-browser-windows\scripts\launch-chrome.ps1`
2. Log into the Atlassian site in that window (first time only).
3. `powershell -ExecutionPolicy Bypass -File skills\atlassian-browser-windows\scripts\atl_cdp.ps1 -Method GET -Path /rest/api/3/myself`

Both print `{"status":200,"ok":true,"data":{...}}`. Pick endpoints from
[`references/atlassian-rest-cookbook.md`](references/atlassian-rest-cookbook.md).

## Cloud vs Server / Data Center

- Cloud (`*.atlassian.net`): Jira `/rest/api/3`, Confluence `/wiki/rest/api`.
- Server/DC (self-hosted): Jira `/rest/api/2`, Confluence `/rest/api`; set the
  host filter (`ATL_HOST` / `-HostFilter`) to a substring of that host's URL.

## Safety

Reads (`GET`, JQL/CQL) are free. **Writes** (`POST`/`PUT`/`DELETE` — create,
update, delete, comment, transition) act on real Jira/Confluence data: state the
exact target and get user approval first; never bulk-delete without explicit
confirmation. Use these skills only when the sanctioned MCP/API paths are
genuinely unavailable.

## Limitations

- Needs a logged-in browser tab open on the target site.
- macOS Safari `do JavaScript` can't await promises, so the wrapper polls for the
  async result (handled for you).
- Self-hosted instances with non-standard reverse proxies may need a tweaked
  `ATL_HOST` and base path.
