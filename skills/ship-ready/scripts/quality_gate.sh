#!/usr/bin/env bash
# Quality gate: detects the project stack and runs every available check
# (format, lint, types, complexity, duplication, tests + coverage, security,
# secrets). Tools that are not installed are reported as SKIPPED, never PASS.
#
# Usage:   quality_gate.sh [project_dir] [--json output.json]
# Exit:    0 all checks that ran passed · 1 a check failed · 3 nothing could run
# Needs:   bash; each check uses its own tool only if it is on PATH.

set -uo pipefail

PROJECT_DIR="."
JSON_OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) [ $# -ge 2 ] || { echo "--json needs a file path" >&2; exit 2; }; JSON_OUT="$2"; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) PROJECT_DIR="$1" ;;
  esac
  shift
done
case "$JSON_OUT" in ""|/*) ;; *) JSON_OUT="$PWD/$JSON_OUT" ;; esac
cd "$PROJECT_DIR" || { echo "cannot cd into $PROJECT_DIR" >&2; exit 2; }

RESULTS=""      # lines of: status<TAB>label<TAB>detail
FAILED=0
EXCLUDES="node_modules,.venv,venv,dist,build,target,.git"

has() { command -v "$1" >/dev/null 2>&1; }
record() { RESULTS="$RESULTS$1	$2	$3
"; }

# run_check <label> <command...>: runs the command if its program is installed.
run_check() {
  local label="$1"; shift
  if ! has "$1"; then record SKIPPED "$label" "$1 not installed"; return; fi
  echo "──▶ $label: $*"
  if "$@"; then record PASS "$label" ""; else record FAIL "$label" "exit $?"; FAILED=1; fi
}

python_checks() {
  echo "== Python =="
  run_check format      ruff format --check .
  run_check lint        ruff check .
  run_check types       mypy --strict --ignore-missing-imports .
  # radon prints nothing for clean code; grade C+ (complexity > 10) fails the check.
  if has radon; then
    local complex; complex="$(radon cc -s -n C -e "$EXCLUDES" . 2>/dev/null)"
    if [ -z "$complex" ]; then record PASS complexity ""
    else echo "$complex"; record FAIL complexity "functions above complexity 10"; FAILED=1; fi
  else record SKIPPED complexity "radon not installed"; fi
  run_check security    bandit -q -r . -ll -x "./tests,./.venv,./venv,./node_modules"
  run_check deps-audit  pip-audit
  if has pytest && python3 -c "import pytest_cov" 2>/dev/null; then
    run_check tests+coverage pytest -q --cov --cov-branch --cov-report=term-missing --cov-fail-under=80
  else
    run_check tests pytest -q
  fi
}

# Project-local Node tools live in node_modules/.bin; prefer them over globals.
node_bin() { if [ -x "node_modules/.bin/$1" ]; then printf '%s' "node_modules/.bin/$1"; else printf '%s' "$1"; fi; }

node_checks() {
  echo "== Node / TypeScript =="
  run_check format "$(node_bin prettier)" --check .
  run_check lint   "$(node_bin eslint)" . --max-warnings=0
  if [ -f tsconfig.json ]; then run_check types "$(node_bin tsc)" --noEmit; fi
  if grep -q '"test"' package.json 2>/dev/null; then run_check tests npm test --silent; fi
  run_check deps-audit npm audit --audit-level=high
}

go_checks() {
  echo "== Go =="
  if has gofmt; then
    local unformatted; unformatted="$(gofmt -l . 2>/dev/null)"
    if [ -z "$unformatted" ]; then record PASS format ""; else record FAIL format "gofmt: $unformatted"; FAILED=1; fi
  fi
  run_check vet            go vet ./...
  run_check lint           golangci-lint run
  run_check tests+coverage go test -race -cover ./...
  run_check security       gosec -quiet ./...
  run_check deps-audit     govulncheck ./...
}

rust_checks() {
  echo "== Rust =="
  run_check format     cargo fmt --check
  run_check lint       cargo clippy --all-targets -- -D warnings
  run_check tests      cargo test
  run_check deps-audit cargo audit
}

jvm_checks() {
  echo "== JVM =="
  if [ -x ./gradlew ]; then run_check build+tests ./gradlew check
  elif [ -f pom.xml ]; then run_check build+tests mvn -q verify
  fi
}

detected=""
if [ -f pyproject.toml ] || [ -f setup.py ] || [ -f requirements.txt ]; then python_checks; detected="$detected python"; fi
if [ -f package.json ]; then node_checks; detected="$detected node"; fi
if [ -f go.mod ]; then go_checks; detected="$detected go"; fi
if [ -f Cargo.toml ]; then rust_checks; detected="$detected rust"; fi
if [ -f pom.xml ] || [ -f build.gradle ] || [ -f build.gradle.kts ]; then jvm_checks; detected="$detected jvm"; fi
[ -n "$detected" ] || echo "No project manifest found (pyproject.toml, package.json, go.mod, Cargo.toml, pom.xml, build.gradle)."

echo "== Stack-independent =="
run_check duplication "$(node_bin jscpd)" --silent --threshold 3 --ignore "**/{$EXCLUDES}/**" .
run_check secrets     gitleaks detect --no-banner --source .
run_check sast        semgrep scan --config auto --error --quiet

ran="$(printf '%s' "$RESULTS" | grep -cvE '^(SKIPPED|$)' || true)"
if [ "$ran" -eq 0 ]; then verdict="NO_CHECKS_RAN"; code=3
elif [ "$FAILED" -eq 0 ]; then verdict="PASS"; code=0
else verdict="FAIL"; code=1; fi

echo
echo "================ QUALITY GATE SUMMARY ================"
printf '%s' "$RESULTS" | awk -F '\t' 'NF { printf "%-8s %-16s %s\n", $1, $2, $3 }'
echo "======================================================"
echo "RESULT: $verdict ($ran checks ran; stack:${detected:- none})"

if [ -n "$JSON_OUT" ]; then
  mkdir -p "$(dirname "$JSON_OUT")"
  {
    printf '{\n  "schema": "ship-ready/gate@1",\n'
    printf '  "date": "%s",\n  "verdict": "%s",\n  "stack": "%s",\n  "checks": [\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$verdict" "${detected# }"
    printf '%s' "$RESULTS" | awk -F '\t' '
      function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
      NF { if (n++) printf ",\n"; printf "    {\"status\": \"%s\", \"check\": \"%s\", \"detail\": \"%s\"}", $1, esc($2), esc($3) }
      END { printf "\n" }'
    printf '  ]\n}\n'
  } > "$JSON_OUT"
  echo "JSON written to $JSON_OUT"
fi
exit $code
