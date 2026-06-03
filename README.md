# atlassian-browser-skills

> 🌐 **한국어** (현재 문서) · [English](README.en.md)

회사 보안 때문에 **Atlassian MCP·API 토큰이 막힌 환경**에서, 사용자가 **이미 로그인해 둔 로컬 브라우저**(Safari/Chrome/Edge)를 구동해 LLM 에이전트로 **Jira·Confluence를 읽고 쓰는** 스킬 모음입니다. API 토큰도, MCP도 필요 없습니다.

## 아이디어

회사 방화벽이 막는 것은 *외부* 접근 경로(Atlassian MCP, 개인 API 토큰)입니다. 정작 사용자가 평소 Jira/Confluence를 여는 **브라우저 자체는 막지 않습니다**. 그래서 외부 API 클라이언트를 쓰는 대신, **인증된 브라우저 탭 안에서 동일 출처(`same-origin`) `fetch()`를 실행**해 Atlassian *자기 자신의* REST API — Jira/Confluence SPA가 내부적으로 쓰는 바로 그 엔드포인트 — 를 호출합니다.

```
LLM 에이전트
  └─ skill (REST cookbook에서 고른 METHOD + PATH + BODY)
       └─ transport: 로그인된 탭에서 JS 실행
            ├─ macOS:   osascript → Safari / Chrome  (do JavaScript / execute javascript)
            └─ Windows: PowerShell/Python → Chrome DevTools Protocol (Runtime.evaluate)
                 └─ fetch(location.origin + PATH)  ← 세션 쿠키 / SSO 자동 포함
                      └─ Atlassian REST API  →  이슈·페이지 CRUD
```

장점: **API 토큰·MCP·추가 로그인 모두 불필요**. 그리고 DOM 스크래핑이 아니라 REST API를 호출하므로 결과가 구조적이고 안정적입니다.

## 구성

```
references/atlassian-rest-cookbook.md      # 공용: 모든 엔드포인트 + 페이로드 (Jira/Confluence, Cloud & DC)
skills/
  atlassian-browser-macos/                 # Safari 또는 Chrome, osascript 사용 (실 세션)
    SKILL.md
    scripts/atl_safari.sh                   #   Safari 래퍼: fetch JS 생성 → osascript 실행 → 폴링
    scripts/safari_atl.applescript          #     탭 찾기 + do JavaScript + 폴링
    scripts/atl_chrome_mac.sh               #   Chrome 래퍼 (인터페이스 동일)
    scripts/chrome_atl.applescript          #     탭 찾기 + execute javascript + 폴링
  atlassian-browser-windows/               # Chrome DevTools Protocol
    SKILL.md
    scripts/atl_cdp.ps1                      #   권장 — 무설치 (윈도 내장 PowerShell)
    scripts/atl_cdp.py                       #   선택 대안 — 순수 stdlib Python (pip 불필요)
    scripts/atl_playwright.py                #   대안 — Playwright (pip), CDP attach
    scripts/launch-chrome.ps1               #   디버그 포트로 Chrome/Edge 실행
```

## macOS — Safari / Chrome (osascript)

macOS의 `osascript`는 *이미 실행 중인* Safari/Chrome에 붙어 JS를 실행합니다. 재실행도, 디버그 포트도, 별도 프로파일도 필요 없이 **로그인된 실 세션을 그대로** 씁니다.

| 브라우저 | 스크립트 | 방식 |
|---|---|---|
| Safari | `atl_safari.sh` | `do JavaScript` |
| Chrome | `atl_chrome_mac.sh` | `execute javascript` |

두 방식 모두 promise를 await할 수 없어, 결과를 `window` 전역에 저장하고 폴링합니다(자동 처리됨).

### 일회성 설정 후 읽기 테스트

**Safari**
1. **개발자용 메뉴 표시:** Safari ▸ 설정…(⌘,) ▸ **고급** ▸ **"웹 개발자용 기능 보기"** 체크
2. **Apple Events JS 허용:** 메뉴 막대 **개발자용** ▸ **"Apple Events의 JavaScript 허용"** 체크
3. **자동화 권한 승인:** 최초 실행 시 팝업에서 허용 (또는 시스템 설정 ▸ 개인정보 보호 및 보안 ▸ **자동화** ▸ 터미널 → **Safari**)
4. Safari 탭에서 Atlassian 사이트에 **로그인**하고 탭을 열어 둠
5. 실행: `skills/atlassian-browser-macos/scripts/atl_safari.sh GET /rest/api/3/myself` → `"status":200` 기대

**Google Chrome** — 토글 하나, 로그인된 실 Chrome 사용
1. **Apple Events JS 허용:** 메뉴 막대 **보기 ▸ 개발자용** ▸ **"Apple Events의 JavaScript 허용"** 체크
2. **자동화 권한 승인** (시스템 설정 ▸ 개인정보 보호 및 보안 ▸ **자동화** ▸ 터미널 → **Google Chrome**)
3. Chrome 탭에서 Atlassian 사이트에 **로그인**하고 탭을 열어 둠
4. 실행: `skills/atlassian-browser-macos/scripts/atl_chrome_mac.sh GET /rest/api/3/myself` → `"status":200` 기대

> 토글을 켜지 않으면 모든 호출이
> `{"status":0,"ok":false,"error":"inject failed: ... Allow JavaScript from Apple Events ..."}`
> 를 반환합니다. 상세: [`skills/atlassian-browser-macos/SKILL.md`](skills/atlassian-browser-macos/SKILL.md)

## Windows — Chrome DevTools Protocol

macOS와 달리 Windows에는 실행 중인 Chrome에 붙는 `osascript` 같은 브리지가 **없습니다**. 로그인된 탭에서 JS를 돌려 결과를 받는 유일한 방법은 디버그 포트의 **CDP**입니다. 다만 CDP *클라이언트*를 **윈도 내장 PowerShell**로 작성했으므로 **설치할 것이 없습니다** — 이것이 osascript에 대응하는 가벼운 기본 내장 답입니다. **Python은 필수가 아닙니다.**

| 클라이언트 | 설치 부담 | 선택 기준 |
|---|---|---|
| **`atl_cdp.ps1`** (PowerShell) | **없음** — 윈도 기본 내장 | ✅ 권장 |
| `atl_cdp.py` (Python) | Python만, **pip 불필요** (stdlib WebSocket) | 선택 — Python으로 다루고 싶을 때 |
| `atl_playwright.py` (Playwright) | `pip install playwright` | 선택 — 이미 Playwright를 표준으로 쓸 때 |

macOS 대비 **유일하게 불가피한 단계**는 Chrome을 한 번 디버그 포트 플래그로 실행하는 것입니다.

```powershell
# 1) 디버그 포트로 Chrome/Edge 실행 (전용 프로파일)
powershell -ExecutionPolicy Bypass -File skills\atlassian-browser-windows\scripts\launch-chrome.ps1
# 2) 그 창에서 Atlassian 사이트에 로그인 (최초 1회)
# 3) 읽기 테스트
powershell -ExecutionPolicy Bypass -File skills\atlassian-browser-windows\scripts\atl_cdp.ps1 -Method GET -Path /rest/api/3/myself
```

> 재로그인조차 피하려면 Chrome을 완전히 종료한 뒤 기존 프로파일로 `--remote-debugging-port=9222 --remote-allow-origins=*`만 붙여 재실행하면 기존 SSO 쿠키가 그대로 쓰입니다. 상세: [`skills/atlassian-browser-windows/SKILL.md`](skills/atlassian-browser-windows/SKILL.md)

## 사용 예시 (엔드포인트 선택)

호출은 **METHOD + PATH + BODY**만 고르면 됩니다. 전체 엔드포인트·페이로드는 [`references/atlassian-rest-cookbook.md`](references/atlassian-rest-cookbook.md) 참고.

```bash
SH=skills/atlassian-browser-macos/scripts/atl_safari.sh   # 또는 atl_chrome_mac.sh

# 읽기
"$SH" GET  /rest/api/3/myself
# JQL 검색
"$SH" POST /rest/api/3/search/jql '{"jql":"project = ABC AND statusCategory != Done","maxResults":20}'
# 이슈 생성 (Cloud는 description에 ADF 사용)
"$SH" POST /rest/api/3/issue '{"fields":{"project":{"key":"ABC"},"issuetype":{"name":"Task"},"summary":"Hello"}}'
# Confluence 페이지 생성 (Cloud는 /wiki 하위)
"$SH" POST /wiki/rest/api/content '{"type":"page","title":"New","space":{"key":"DOCS"},"body":{"storage":{"value":"<p>hi</p>","representation":"storage"}}}'
```

모든 호출은 `{"status":200,"ok":true,"data":{...}}` JSON을 반환합니다.

## Cloud vs Server / Data Center

- Cloud (`*.atlassian.net`): Jira `/rest/api/3`, Confluence `/wiki/rest/api`
- Server/DC (자체 호스팅): Jira `/rest/api/2`, Confluence `/rest/api`. 호스트 필터(`ATL_HOST` / `-HostFilter`)를 해당 호스트 URL의 일부로 지정.

## 안전 수칙

읽기(`GET`, JQL/CQL)는 자유롭게 가능합니다. **쓰기**(`POST`/`PUT`/`DELETE` — 생성·수정·삭제·댓글·전환)는 실제 Jira/Confluence 데이터를 바꿉니다. 대상을 명시하고 사용자 승인을 먼저 받으세요. 명시적 확인 없이 대량 삭제하지 마세요. 정식 MCP/API 경로가 가능하다면 그쪽을 우선 사용하세요.

## 제약

- 대상 사이트에 로그인된 브라우저 탭이 열려 있어야 합니다.
- macOS의 `do JavaScript`/`execute javascript`는 promise를 await할 수 없어 폴링으로 결과를 받습니다(자동 처리).
- 비표준 리버스 프록시를 쓰는 자체 호스팅 인스턴스는 `ATL_HOST`와 base path 조정이 필요할 수 있습니다.

## 라이선스

[MIT](LICENSE)
