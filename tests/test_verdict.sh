#!/usr/bin/env bash
# Tests for skills/ship-ready/scripts/verdict.py: every verdict rule and exit code.
#
# Usage: tests/test_verdict.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V="$ROOT/skills/ship-ready/scripts/verdict.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
passed=0; failed=0

expect() {   # expect <description> <exit_code> <args...>
  local want="$2"; shift 2
  python3 "$V" "$@" >/dev/null 2>&1; local got=$?
  if [ "$got" -eq "$want" ]; then passed=$((passed + 1)); echo "ok    $DESC"
  else failed=$((failed + 1)); echo "FAIL  $DESC (exit $got, want $want)"; fi
}

cd "$TMP" || exit 1
echo '{"checks":[{"status":"PASS","check":"tests"},{"status":"PASS","check":"lint"}]}' > ok.json
echo '{"checks":[{"status":"PASS","check":"tests"},{"status":"SKIPPED","check":"sast","detail":"semgrep not installed"}]}' > skip.json
echo '{"checks":[{"status":"PASS","check":"tests"},{"status":"FAIL","check":"lint"}]}' > fail.json
echo '{"checks":[{"status":"SKIPPED","check":"tests","detail":"pytest not installed"}]}' > none.json
echo '{"findings":[{"id":"F-1","severity":"P0","status":"fixed"},{"id":"F-2","severity":"P2","status":"open"}]}' > clean.json
echo '{"findings":[{"id":"F-1","severity":"P0","status":"open"}]}' > p0.json
echo '{"findings":[{"id":"F-1","severity":"P1","status":"needs_verification"}]}' > p1.json
echo '{"findings":[{"id":"F-1","severity":"P0","status":"capped_not_converged"}]}' > capped.json

DESC="all gates pass, no open P0/P1 -> READY";            expect "$DESC" 0 ok.json clean.json
DESC="skipped gate -> READY_WITH_CONDITIONS";             expect "$DESC" 1 skip.json clean.json
DESC="no report supplied -> READY_WITH_CONDITIONS";       expect "$DESC" 1 ok.json
DESC="open P1 -> READY_WITH_CONDITIONS";                  expect "$DESC" 1 ok.json p1.json
DESC="failed gate -> NOT_READY";                          expect "$DESC" 2 fail.json clean.json
DESC="open P0 -> NOT_READY";                              expect "$DESC" 2 ok.json p0.json
DESC="capped P0 counts as open -> NOT_READY";             expect "$DESC" 2 ok.json capped.json
DESC="no checks ran -> NOT_READY";                        expect "$DESC" 2 none.json clean.json
DESC="unreadable input -> exit 3";                        expect "$DESC" 3 missing.json
DESC="no arguments -> exit 3";                            expect "$DESC" 3

cp clean.json w.json; python3 "$V" skip.json w.json --write >/dev/null
DESC="--write stores computed verdict"
if python3 -c "import json,sys; d=json.load(open('w.json')); sys.exit(d['verdict']!='READY_WITH_CONDITIONS')"; then
  passed=$((passed + 1)); echo "ok    $DESC"; else failed=$((failed + 1)); echo "FAIL  $DESC"; fi

echo "---"; echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
