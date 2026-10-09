#!/usr/bin/env bash
# Ranks source files by change frequency × size, a cheap proxy for where
# defects and maintenance cost concentrate. Work the top of this list first.
#
# Usage:  hotspots.sh [repo_dir] [top_n=20] [since="12 months ago"]
# Output: score  commits  lines  path      (score = commits × lines)
# Needs:  bash, git. Outside a git repository, falls back to size only.

set -euo pipefail

REPO="${1:-.}"
TOP="${2:-20}"
SINCE="${3:-12 months ago}"
cd "$REPO"

SOURCE_RE='\.(py|js|jsx|ts|tsx|java|kt|go|rs|rb|php|cs|cpp|cc|c|h|hpp|swift|scala)$'
SKIP_RE='(^|/)(node_modules|vendor|dist|build|target|\.venv|venv|__pycache__|migrations|generated)/|\.min\.js$|_pb2\.py$'

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository: ranking by size only." >&2
  find . -type f | grep -E "$SOURCE_RE" | grep -vE "$SKIP_RE" | sed 's|^\./||' \
    | while IFS= read -r f; do printf '%s\t%s\n' "$(wc -l < "$f" | tr -d ' ')" "$f"; done \
    | sort -rn | head -n "$TOP" | awk -F '\t' 'BEGIN { print "lines\tpath" } { print $1 "\t" $2 }'
  exit 0
fi

printf 'score\tcommits\tlines\tpath\n'
git log --since="$SINCE" --format= --name-only --no-merges -- . \
  | grep -E "$SOURCE_RE" | grep -vE "$SKIP_RE" | sort | uniq -c \
  | while read -r commits path; do
      [ -f "$path" ] || continue                       # deleted or renamed since
      lines="$(wc -l < "$path" | tr -d ' ')"
      printf '%s\t%s\t%s\t%s\n' "$((commits * lines))" "$commits" "$lines" "$path"
    done \
  | sort -rn | head -n "$TOP"
