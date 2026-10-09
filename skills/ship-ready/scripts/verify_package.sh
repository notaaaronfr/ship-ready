#!/usr/bin/env bash
# Verifies that a dependency exists in its public registry and is not
# suspiciously new, before an agent adds it. Defends against hallucinated
# package names and "slopsquatting".
#
# Usage:  verify_package.sh <pypi|npm|crates|go> <name> [<name> ...]
# Exit:   0 all OK · 1 a package does not exist · 2 usage/network error · 4 needs human review
# Needs:  bash, curl, python3 (for JSON parsing). Requires network access.

set -uo pipefail

MIN_AGE_DAYS=90          # packages younger than this need human review
UA="ship-ready-skill/verify_package"

[ $# -ge 2 ] || { sed -n '2,9p' "$0"; exit 2; }
ECOSYSTEM="$1"; shift
command -v curl >/dev/null && command -v python3 >/dev/null || { echo "needs curl and python3" >&2; exit 2; }

# fetch <url>: prints the body, returns 44 on HTTP 404, 2 on other errors.
fetch() {
  local body status
  body="$(curl -sS -A "$UA" --max-time 15 -w '\n%{http_code}' "$1")" || return 2
  status="${body##*$'\n'}"; body="${body%$'\n'*}"
  [ "$status" = "404" ] && return 44
  [ "$status" -ge 200 ] && [ "$status" -lt 300 ] || return 2
  printf '%s' "$body"
}

# Python reads the registry JSON on stdin and prints: first_release_iso, summary, repo (separated by 0x1F)
extract() {
  python3 -I -c "
import json, sys
eco = sys.argv[1]; d = json.load(sys.stdin)
if eco == 'pypi':
    times = [f['upload_time_iso_8601'] for files in d.get('releases', {}).values() for f in files]
    info = d['info']; urls = info.get('project_urls') or {}
    repo = next((u for k, u in urls.items() if k.lower() in ('source', 'repository', 'code', 'homepage')), '')
    print(min(times) if times else '', info.get('summary') or '', repo, sep='\x1f')
elif eco == 'npm':
    t = d.get('time', {}); repo = d.get('repository') or {}
    print(t.get('created', ''), d.get('description') or '', repo.get('url', '') if isinstance(repo, dict) else repo, sep='\x1f')
elif eco == 'crates':
    c = d['crate']
    print(c.get('created_at', ''), c.get('description') or '', c.get('repository') or '', sep='\x1f')
elif eco == 'go':
    print(d.get('Time', ''), '', (d.get('Origin') or {}).get('URL', '') or 'https://' + sys.argv[2], sep='\x1f')
" "$ECOSYSTEM" "$name"
}

age_days() {
  python3 -I -c "
import sys, datetime as dt
t = dt.datetime.strptime(sys.argv[1][:19], '%Y-%m-%dT%H:%M:%S')   # registries report UTC
print((dt.datetime.utcnow() - t).days)" "$1" 2>/dev/null || echo ""
}

# The Go proxy has no "created" field: look up the oldest tagged version instead.
go_first_version_url() {
  local base first
  base="https://proxy.golang.org/$(printf '%s' "$1" | sed 's/[A-Z]/!&/g' | tr 'A-Z' 'a-z')"
  first="$(fetch "$base/@v/list" | grep -E '^v[0-9]' | sort -t. -k1,1V -k2,2n -k3,3n 2>/dev/null | head -n 1)"
  [ -n "$first" ] || first="$(fetch "$base/@v/list" | head -n 1)"
  [ -n "$first" ] || return 1
  printf '%s/@v/%s.info' "$base" "$first"
}

worst=0
for name in "$@"; do
  case "$ECOSYSTEM" in
    pypi)   url="https://pypi.org/pypi/$name/json" ;;
    npm)    url="https://registry.npmjs.org/$(printf '%s' "$name" | sed 's|/|%2F|')" ;;
    crates) url="https://crates.io/api/v1/crates/$name" ;;
    go)     url="$(go_first_version_url "$name")" || { echo "MISSING  go:$name  no published versions. Possibly hallucinated; do not add."; worst=1; continue; } ;;
    *)      echo "unknown ecosystem: $ECOSYSTEM (pypi|npm|crates|go)" >&2; exit 2 ;;
  esac

  body="$(fetch "$url")"; rc=$?
  if [ $rc -eq 44 ]; then
    echo "MISSING  $ECOSYSTEM:$name  does not exist. Possibly hallucinated; do not add."
    worst=1; continue
  elif [ $rc -ne 0 ]; then
    echo "ERROR    $ECOSYSTEM:$name  registry lookup failed (network?)"; [ $worst -eq 0 ] && worst=2; continue
  fi

  IFS=$'\x1f' read -r created summary repo <<<"$(printf '%s' "$body" | extract)"
  age="$( [ -n "$created" ] && age_days "$created" )"
  notes=""
  [ -z "$repo" ] && notes="$notes no-repository-link;"
  if [ -n "$age" ] && [ "$age" -lt "$MIN_AGE_DAYS" ]; then notes="$notes first-published-${age}-days-ago;"; fi

  if [ -n "$notes" ]; then
    echo "REVIEW   $ECOSYSTEM:$name  age=${age:-?}d repo=${repo:-none}  flags:$notes"
    [ $worst -eq 0 ] && worst=4
  else
    echo "OK       $ECOSYSTEM:$name  age=${age:-?}d repo=$repo  ${summary:0:70}"
  fi
done

[ $worst -ne 0 ] && echo "Check download counts and maintainers, and look for typosquats of popular names, before adding anything flagged."
exit $worst
