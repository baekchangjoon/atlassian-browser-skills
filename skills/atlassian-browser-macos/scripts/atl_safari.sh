#!/usr/bin/env bash
# atl_safari.sh — run an authenticated Atlassian REST call inside the user's
# logged-in Safari tab (macOS). No API token, no MCP: uses the existing browser
# session cookie via a same-origin fetch().
#
# usage:
#   atl_safari.sh <METHOD> <PATH> [BODY_JSON]
#   echo '<BODY_JSON>' | atl_safari.sh <METHOD> <PATH> -
#
# examples:
#   atl_safari.sh GET  /rest/api/3/myself
#   atl_safari.sh POST /rest/api/3/search/jql '{"jql":"project=ABC","maxResults":5}'
#   atl_safari.sh PUT  /rest/api/3/issue/ABC-1 '{"fields":{"summary":"new"}}'
#
# env:
#   ATL_HOST        substring to match the target tab URL (default: atlassian)
#   ATL_TIMEOUT_MS  poll timeout in ms (default: 30000)
#
# Prints {"status":..,"ok":..,"data":..} JSON on stdout.
#
# One-time setup: Safari > Settings > Advanced > "Show Develop menu",
# then Develop > "Allow JavaScript from Apple Events".

set -euo pipefail

METHOD="${1:-}"
PATH_ARG="${2:-}"
BODY="${3:-}"

if [[ -z "$METHOD" || -z "$PATH_ARG" ]]; then
  echo '{"status":0,"ok":false,"error":"usage: atl_safari.sh METHOD PATH [BODY_JSON|-]"}'
  exit 2
fi

# Read body from stdin when third arg is "-"
if [[ "$BODY" == "-" ]]; then
  BODY="$(cat)"
fi

# BODY becomes a JS literal: a valid JSON object/array, or `null` when empty.
if [[ -z "$BODY" ]]; then
  BODY_JS="null"
else
  BODY_JS="$BODY"
fi

HOST="${ATL_HOST:-atlassian}"
TIMEOUT_MS="${ATL_TIMEOUT_MS:-30000}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Build the injected JS. It kicks off the fetch and stashes the result on
# window globals; the AppleScript side polls __ATL_DONE (Safari's do JavaScript
# cannot await promises, so we poll).
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

osascript "$DIR/safari_atl.applescript" "$HOST" "$B64" "$TIMEOUT_MS"
