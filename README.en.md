# atlassian-browser-skills

> 🌐 [한국어](README.md) · **English** (this page)

<p align="center">
  <a href="https://github.com/baekchangjoon/atlassian-browser-skills/actions/workflows/test-atlassian-browser-macos.yml"><img alt="macOS tests" src="https://github.com/baekchangjoon/atlassian-browser-skills/actions/workflows/test-atlassian-browser-macos.yml/badge.svg"></a>
  <a href="https://github.com/baekchangjoon/atlassian-browser-skills/actions/workflows/test-atlassian-browser-windows.yml"><img alt="Windows tests" src="https://github.com/baekchangjoon/atlassian-browser-skills/actions/workflows/test-atlassian-browser-windows.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-yellow.svg"></a>
  <a href="https://github.com/baekchangjoon/atlassian-browser-skills/releases"><img alt="release" src="https://img.shields.io/github/v/release/baekchangjoon/atlassian-browser-skills?display_name=release&label=release"></a>
  <a href="https://agentskills.io"><img alt="Skill" src="https://img.shields.io/badge/Skill-Claude%20Code%20%7C%20Cursor%20%7C%20Codex%20%7C%20Gemini%20CLI-blueviolet"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/Platforms-macOS%20%7C%20Windows-informational">
  <a href="README.md"><img alt="Docs" src="https://img.shields.io/badge/Docs-KO%20%7C%20EN-green"></a>
</p>

Read/write **Jira & Confluence** from an LLM agent **when the Atlassian MCP and
API tokens are blocked or unavailable** — by driving the user's own
already-logged-in **local browser** (Safari/Chrome/Edge). No API token, no MCP.

## Install

### Claude Code (plugin marketplace — recommended)
This repo is a Claude Code plugin marketplace. Inside Claude Code:
```text
/plugin marketplace add baekchangjoon/atlassian-browser-skills
/plugin install atlassian-browser-skills@atlassian-browser-skills
/reload-plugins
```
Installing brings in both skills (`atlassian-browser-macos`, `atlassian-browser-windows`); the model invokes the right one per OS and task.

### Skills only (no plugin system)
Works in any [Agent Skills](https://agentskills.io)-compatible agent (Claude Code/Claude.ai/Cursor/Gemini CLI, …) — just copy the skill folder:
```bash
git clone https://github.com/baekchangjoon/atlassian-browser-skills
cp -r atlassian-browser-skills/skills/atlassian-browser-macos   ~/.claude/skills/   # macOS
cp -r atlassian-browser-skills/skills/atlassian-browser-windows ~/.claude/skills/   # Windows
```
> The skills reference a shared cookbook at the repo root
> (`references/atlassian-rest-cookbook.md`). When copying a skill standalone, keep
> that path alongside it (it is bundled automatically with the plugin install).

### Getting updates

Third-party marketplaces have **auto-update OFF by default** in Claude Code, so
new releases don't reach your install on their own. Pick one:

- **Manual update** — when a new version ships:
  ```text
  /plugin marketplace update atlassian-browser-skills
  /plugin update atlassian-browser-skills@atlassian-browser-skills
  ```
- **Enable auto-update** (one-time, recommended): `/plugin` → **Marketplaces**
  tab → select `atlassian-browser-skills` → **Enable auto-update**. New versions
  are then picked up automatically when Claude Code starts.

## The idea

What's blocked are the *external* access paths (the Atlassian MCP, personal API
tokens). The browser the user already uses to open Jira/Confluence is **not**
blocked. So instead of an external API client, we execute a
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
| **CDP via PowerShell** (`atl_cdp.ps1`) | **nothing** — PS 5.1 + Chrome are already on virtually every Windows machine | ✅ recommended |
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

## Privacy

This skill/plugin **collects, stores, and transmits no personal data.**

- Everything runs **inside the user's own local browser session** (driven via
  osascript on macOS or the Chrome DevTools Protocol on Windows).
- The only network calls are *the user's browser → the user's own Atlassian
  instance* — exactly what the browser already does. **Nothing is sent to any
  third-party server** by this project.
- It **never handles or stores** API tokens, passwords, or credentials; it relies
  only on the browser's existing session cookie.
- **No analytics, no telemetry**, no background data collection.

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
