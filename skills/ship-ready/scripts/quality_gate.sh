#!/usr/bin/env bash
# Quality gate: detects the project stack and runs every available check
# (format, lint, types, complexity, duplication, tests + coverage, security,
# secrets). Tools that are not installed are reported as SKIPPED, never PASS.
#
# Usage:   quality_gate.sh [project_dir] [--json output.json] [--findings report.json]
#          Ends by printing the ship-ready VERDICT (computed by verdict.py from these
#          results and any open findings; .quality/report.json is used when present).
# Exit:    0 all checks that ran passed · 1 a check failed · 3 nothing could run
# Needs:   bash; each check uses its own tool only if it is on PATH.

set -uo pipefail

PROJECT_DIR="."
JSON_OUT=""
FINDINGS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) [ $# -ge 2 ] || { echo "--json needs a file path" >&2; exit 2; }; JSON_OUT="$2"; shift ;;
    --findings) [ $# -ge 2 ] || { echo "--findings needs a file path" >&2; exit 2; }; FINDINGS="$2"; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) PROJECT_DIR="$1" ;;
  esac
  shift
done
case "$JSON_OUT" in ""|/*) ;; *) JSON_OUT="$PWD/$JSON_OUT" ;; esac
case "$FINDINGS" in ""|/*) ;; *) FINDINGS="$PWD/$FINDINGS" ;; esac
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR" || { echo "cannot cd into $PROJECT_DIR" >&2; exit 2; }

RESULTS=""      # lines of: status<TAB>label<TAB>detail
FAILED=0
EXCLUDES="node_modules,.venv,venv,dist,build,target,.git"

has() { command -v "$1" >/dev/null 2>&1; }
record() { RESULTS="$RESULTS$1	$2	$3
"; }

# True if a Python module is importable (tools installed with pip often are
# runnable as `python3 -m tool` even when the `tool` command is not on PATH).
has_module() { command -v python3 >/dev/null 2>&1 && python3 -c "import $1" 2>/dev/null; }

# run_check <label> <command...>: runs the command if it is installed, falling
# back to `python3 -m <module>` for pip-installed Python tools.
run_check() {
  local label="$1" mod; shift
  if ! has "$1"; then
    mod="$(printf '%s' "$1" | tr '-' '_')"
    if has_module "$mod"; then set -- python3 -m "$mod" "${@:2}"
    else record SKIPPED "$label" "$1 not installed"; return; fi
  fi
  echo "──▶ $label: $*"
  if "$@"; then record PASS "$label" ""; else record FAIL "$label" "exit $?"; FAILED=1; fi
}

python_checks() {
  echo "== Python =="
  run_check format      ruff format --check .
  run_check lint        ruff check .
  run_check types       mypy --strict --ignore-missing-imports .
  # radon prints nothing for clean code; grade C+ (complexity > 10) fails the check.
  local radon_cmd=""
  if has radon; then radon_cmd="radon"; elif has_module radon; then radon_cmd="python3 -m radon"; fi
  if [ -n "$radon_cmd" ]; then
    local complex; complex="$($radon_cmd cc -s -n C -e "$EXCLUDES" . 2>/dev/null)"
    if [ -z "$complex" ]; then record PASS complexity ""
    else echo "$complex"; record FAIL complexity "functions above complexity 10"; FAILED=1; fi
  else record SKIPPED complexity "radon not installed"; fi
  run_check security    bandit -q -r . -ll -x "./tests,./.venv,./venv,./node_modules"
  # Audit the project's declared dependencies, not whatever happens to be installed.
  if [ -f requirements.txt ]; then run_check deps-audit pip-audit -r requirements.txt
  elif grep -qE '^dependencies *= *\[ *[^] ]' pyproject.toml 2>/dev/null; then run_check deps-audit pip-audit .
  else record PASS deps-audit "nothing to audit: no declared dependencies"; fi
  if { has pytest || has_module pytest; } && has_module pytest_cov; then
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

# The verdict needs the JSON, so write it to a temporary file when --json wasn't given.
GATE_JSON="$JSON_OUT"
[ -n "$GATE_JSON" ] || GATE_JSON="$(mktemp)"
if [ -n "$GATE_JSON" ]; then
  mkdir -p "$(dirname "$GATE_JSON")"
  {
    printf '{\n  "schema": "ship-ready/gate@1",\n'
    printf '  "date": "%s",\n  "verdict": "%s",\n  "stack": "%s",\n  "checks": [\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$verdict" "${detected# }"
    printf '%s' "$RESULTS" | awk -F '\t' '
      function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
      NF { if (n++) printf ",\n"; printf "    {\"status\": \"%s\", \"check\": \"%s\", \"detail\": \"%s\"}", $1, esc($2), esc($3) }
      END { printf "\n" }'
    printf '  ]\n}\n'
  } > "$GATE_JSON"
  [ -n "$JSON_OUT" ] && echo "JSON written to $JSON_OUT"
fi

# Ship-ready verdict, computed from evidence. Copy it into the report verbatim.
[ -n "$FINDINGS" ] || { [ -f .quality/report.json ] && FINDINGS="$PWD/.quality/report.json"; }
if command -v python3 >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/verdict.py" ]; then
  echo
  if [ -n "$FINDINGS" ]; then python3 -I "$SCRIPT_DIR/verdict.py" "$GATE_JSON" "$FINDINGS" || true
  else python3 -I "$SCRIPT_DIR/verdict.py" "$GATE_JSON" || true; fi
fi
[ -n "$JSON_OUT" ] || rm -f "$GATE_JSON"
exit $code
