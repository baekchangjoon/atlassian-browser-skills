#!/usr/bin/env bash
# Tests for the macOS Safari/Chrome transport.
#
# Runs entirely WITHOUT a browser or Automation (Apple Events) permission, so it
# is safe in CI (GitHub macos-latest) and locally. It covers what is reachable
# without a GUI session:
#   1. bash syntax of the wrapper scripts
#   2. AppleScript compiles (osacompile — no Apple events sent)
#   3. arg-validation path returns a well-formed JSON error + exit code 2
#   4. the fetch JS the wrapper generates is valid (osascript stubbed, so the
#      real script logic runs but no Apple event is sent)
#
# Driving Safari/Chrome themselves is intentionally NOT tested here: it needs a
# logged-in tab + TCC Automation permission, neither of which exists in CI.
#
# usage:  bash skills/atlassian-browser-macos/tests/test_macos.sh
set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$SKILL_DIR/scripts"
fail=0
pass() { printf '  \033[32m✔\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✖\033[0m %s\n' "$1"; fail=1; }

echo "1. bash syntax"
for f in atl_safari.sh atl_chrome_mac.sh; do
  if bash -n "$SCRIPTS/$f"; then pass "$f parses"; else bad "$f: bash -n failed"; fi
done

echo "2. AppleScript compiles"
for f in safari_atl.applescript chrome_atl.applescript; do
  tmp="$(mktemp -d)/out.scpt"
  if osacompile -o "$tmp" "$SCRIPTS/$f" 2>/tmp/osa.err; then
    pass "$f compiles"
  else
    bad "$f: osacompile failed — $(cat /tmp/osa.err)"
  fi
done

echo "3. arg validation → JSON error + exit 2"
for f in atl_safari.sh atl_chrome_mac.sh; do
  out="$("$SCRIPTS/$f" 2>/dev/null)"; code=$?
  if [ "$code" -eq 2 ] && printf '%s' "$out" | python3 -c '
import sys, json
d = json.load(sys.stdin)
sys.exit(0 if d.get("ok") is False and d.get("status") == 0 and "usage" in d.get("error","") else 1)
'; then
    pass "$f no-args → {ok:false,status:0}, exit 2"
  else
    bad "$f no-args unexpected (exit $code): $out"
  fi
done

echo "4. generated fetch JS is valid (osascript stubbed)"
# Stub osascript so the wrapper runs its real JS-building + base64 logic but
# sends no Apple event. The stub prints arg 3 (the base64 payload) back.
STUB="$(mktemp -d)"
cat >"$STUB/osascript" <<'STUBEOF'
#!/usr/bin/env bash
# wrapper calls: osascript <applescript> <hostFilter> <b64> <timeoutMs>
printf '%s' "$3"
STUBEOF
chmod +x "$STUB/osascript"

if ! command -v node >/dev/null 2>&1; then
  echo "  (node unavailable — skipping JS-validity check)"
else
  for f in atl_safari.sh atl_chrome_mac.sh; do
    b64="$(PATH="$STUB:$PATH" "$SCRIPTS/$f" POST /rest/api/3/search/jql '{"jql":"project = ABC","maxResults":5}')"
    if printf '%s' "$b64" | base64 -d | node --check - 2>/tmp/node.err; then
      pass "$f → generates syntactically valid JS"
    else
      bad "$f → generated invalid JS: $(cat /tmp/node.err)"
    fi
  done
fi

echo
if [ "$fail" -ne 0 ]; then echo "FAILED"; exit 1; fi
echo "ALL PASSED"
