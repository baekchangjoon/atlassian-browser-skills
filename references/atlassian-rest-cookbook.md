# Atlassian REST cookbook (browser-session edition)

This is the **knowledge layer** shared by all transports (macOS Safari, Windows
Chrome). The transport only does one thing:

> Run an authenticated `fetch(origin + PATH, {method, body})` **inside the user's
> logged-in Atlassian tab** and return `{status, ok, data}`.

Because the request runs in the page origin, the browser session cookie (incl.
corporate SSO) is sent automatically. You never handle tokens. You just pick the
right **METHOD + PATH + BODY** from this cookbook.

The transport scripts take exactly three inputs:

| arg    | meaning                                            |
|--------|----------------------------------------------------|
| METHOD | `GET` `POST` `PUT` `DELETE`                         |
| PATH   | path **relative to the site origin**, e.g. `/rest/api/3/issue/ABC-1` |
| BODY   | JSON string for writes, or omitted/`null` for reads |

Writes automatically get `Content-Type: application/json` and
`X-Atlassian-Token: no-check` (defeats Atlassian's XSRF guard for cookie auth).

---

## Cloud vs Server / Data Center

| product            | Cloud base path        | Server / DC base path |
|--------------------|------------------------|-----------------------|
| Jira               | `/rest/api/3`          | `/rest/api/2`         |
| Jira Agile         | `/rest/agile/1.0`      | `/rest/agile/1.0`     |
| Confluence content | `/wiki/rest/api`       | `/rest/api`           |
| Confluence v2      | `/wiki/api/v2`         | (n/a)                 |

Detect quickly by looking at the tab URL:
- `*.atlassian.net` → **Cloud**. Confluence lives under `/wiki`.
- self-hosted host (e.g. `jira.company.com`) → **Server / DC** (API v2 / no `/wiki`).

When unsure, do a cheap read first: `GET /rest/api/3/myself` (Cloud Jira) vs
`GET /rest/api/2/myself` (DC).

---

## Jira — Cloud (`/rest/api/3`)

### Read
- Current user: `GET /rest/api/3/myself`
- Get issue: `GET /rest/api/3/issue/ABC-123`
- Get issue (selected fields): `GET /rest/api/3/issue/ABC-123?fields=summary,status,assignee`
- **Search by JQL** (the old `GET /search` is deprecated — use this):
  ```
  POST /rest/api/3/search/jql
  {"jql":"project = ABC AND statusCategory != Done ORDER BY created DESC",
   "maxResults":50,"fields":["summary","status","assignee"]}
  ```
- List projects: `GET /rest/api/3/project/search`
- Create/edit metadata: `GET /rest/api/3/issue/createmeta?projectKeys=ABC&expand=projects.issuetypes.fields`
- Transitions available: `GET /rest/api/3/issue/ABC-123/transitions`

### Create issue
```
POST /rest/api/3/issue
{"fields":{
  "project":{"key":"ABC"},
  "issuetype":{"name":"Task"},
  "summary":"Title here",
  "description":{"type":"doc","version":1,"content":[
    {"type":"paragraph","content":[{"type":"text","text":"Body text"}]}]}
}}
```
> Cloud uses **ADF** (Atlassian Document Format) for `description`/comment bodies.
> For a plain paragraph use the shape above.

### Update issue
```
PUT /rest/api/3/issue/ABC-123
{"fields":{"summary":"New title"}}
```

### Add comment
```
POST /rest/api/3/issue/ABC-123/comment
{"body":{"type":"doc","version":1,"content":[
  {"type":"paragraph","content":[{"type":"text","text":"My comment"}]}]}}
```

### Transition (e.g. move to Done)
```
# 1) find the transition id:
GET /rest/api/3/issue/ABC-123/transitions
# 2) apply it:
POST /rest/api/3/issue/ABC-123/transitions
{"transition":{"id":"31"}}
```

### Delete issue
```
DELETE /rest/api/3/issue/ABC-123
```

---

## Jira — Server / Data Center (`/rest/api/2`)

Same shapes as Cloud **but**:
- base path is `/rest/api/2`
- `description` / comment `body` are **plain strings (wiki markup)**, not ADF:
  ```
  POST /rest/api/2/issue
  {"fields":{"project":{"key":"ABC"},"issuetype":{"name":"Task"},
             "summary":"Title","description":"Plain text body"}}
  ```
- Search: `POST /rest/api/2/search` with `{"jql":"...","maxResults":50}`

---

## Confluence — Cloud (`/wiki/rest/api`)

### Read
- Get page (with body): `GET /wiki/rest/api/content/123456?expand=body.storage,version,space`
- Search by CQL: `GET /wiki/rest/api/content/search?cql=space=DOCS%20and%20type=page&limit=25`
- List spaces: `GET /wiki/rest/api/space?limit=50`
- Find page by title: `GET /wiki/rest/api/content?spaceKey=DOCS&title=My%20Page&expand=version`

### Create page
```
POST /wiki/rest/api/content
{"type":"page","title":"New Page","space":{"key":"DOCS"},
 "body":{"storage":{"value":"<p>Hello world</p>","representation":"storage"}}}
```
Optional parent: add `"ancestors":[{"id":"123456"}]`.

### Update page (must bump version)
```
# 1) read current version number:
GET /wiki/rest/api/content/123456?expand=version
# 2) PUT with version+1:
PUT /wiki/rest/api/content/123456
{"id":"123456","type":"page","title":"Updated Title","version":{"number":<current+1>},
 "body":{"storage":{"value":"<p>New body</p>","representation":"storage"}}}
```

### Add comment to a page
```
POST /wiki/rest/api/content
{"type":"comment","container":{"id":"123456","type":"page"},
 "body":{"storage":{"value":"<p>My comment</p>","representation":"storage"}}}
```

### Delete page
```
DELETE /wiki/rest/api/content/123456
```
> Confluence Cloud delete is two-stage: this moves the page to **trash** (a
> following `GET` returns 404). To purge permanently, call again with
> `DELETE /wiki/rest/api/content/123456?status=trashed`.

---

## Confluence — Server / Data Center (`/rest/api`)

Same payloads as Cloud, just drop the `/wiki` prefix:
- `GET /rest/api/content/123456?expand=body.storage,version`
- `POST /rest/api/content` (same body shape)

---

## Result shape

Every transport returns JSON like:
```json
{"status":200,"ok":true,"data":{ ...the Atlassian JSON... }}
```
- `ok:false` with `status:401/403` → session not logged in / wrong origin tab.
- `status:404` → wrong base path (Cloud vs DC mismatch) or bad id/key.
- `status:400` with `data.errors` → payload problem (read the message).
- `status:0` with `error` → fetch threw (network / no tab).

## Tips
- Always operate on a tab already showing the target site so `location.origin` is
  correct. The transports auto-pick a tab whose URL matches the host filter
  (`atlassian` by default; override for self-hosted hosts).
- URL-encode query params (spaces → `%20`) when building PATH.
- For large reads, pass `?maxResults=` / `&limit=` to keep responses small.
