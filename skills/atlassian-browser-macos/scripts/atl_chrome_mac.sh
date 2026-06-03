#!/usr/bin/env bash
# atl_chrome_mac.sh — Google Chrome (macOS) twin of atl_safari.sh. Runs an
# authenticated Atlassian REST call inside the user's LIVE logged-in Chrome tab
# via osascript. No API token, no MCP, no debug port, no separate profile —
# uses the existing browser session cookie via a same-origin fetch().
#
# usage:
#   atl_chrome_mac.sh <METHOD> <PATH> [BODY_JSON]
#   echo '<BODY_JSON>' | atl_chrome_mac.sh <METHOD> <PATH> -
#
# examples:
#   atl_chrome_mac.sh GET  /rest/api/3/myself
#   atl_chrome_mac.sh POST /rest/api/3/search/jql '{"jql":"project=ABC","maxResults":5}'
#
# env:
#   ATL_HOST        substring to match the target tab URL (default: atlassian)
#   ATL_TIMEOUT_MS  poll timeout in ms (default: 30000)
#
# Prints {"status":..,"ok":..,"data":..} JSON on stdout.
#
# One-time setup: Chrome menu bar > View > Developer >
# "Allow JavaScript from Apple Events".

set -euo pipefail

METHOD="${1:-}"
PATH_ARG="${2:-}"
BODY="${3:-}"

if [[ -z "$METHOD" || -z "$PATH_ARG" ]]; then
  echo '{"status":0,"ok":false,"error":"usage: atl_chrome_mac.sh METHOD PATH [BODY_JSON|-]"}'
  exit 2
fi

if [[ "$BODY" == "-" ]]; then
  BODY="$(cat)"
fi

if [[ -z "$BODY" ]]; then
  BODY_JS="null"
else
  BODY_JS="$BODY"
fi

HOST="${ATL_HOST:-atlassian}"
TIMEOUT_MS="${ATL_TIMEOUT_MS:-30000}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Chrome's `execute javascript` (like Safari's do JavaScript) returns
# synchronously and cannot await a promise, so we stash the fetch result on
# window globals and the AppleScript side polls __ATL_DONE.
read -r -d '' JS <<JSEOF || true
(function(){
window.__ATL_DONE=false;window.__ATL_RESULT=null;
var opts={method:"${METHOD}",credentials:"include",headers:{"Accept":"application/json"}};
var __b=${BODY_JS};
if(__b!==null){opts.headers["Content-Type"]="application/json";opts.headers["X-Atlassian-Token"]="no-check";opts.body=JSON.stringify(__b);}
fetch(location.origin+"${PATH_ARG}",opts).then(function(r){return r.text().then(function(t){var d;try{d=JSON.parse(t)}catch(e){d=t}window.__ATL_RESULT={status:r.status,ok:r.ok,data:d};window.__ATL_DONE=true;});}).catch(function(e){window.__ATL_RESULT={status:0,ok:false,error:String(e)};window.__ATL_DONE=true;});
})();
JSEOF

B64="$(printf '%s' "$JS" | base64 | tr -d '\n')"

osascript "$DIR/chrome_atl.applescript" "$HOST" "$B64" "$TIMEOUT_MS"
