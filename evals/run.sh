#!/usr/bin/env bash
# Runs one eval scenario in a throwaway git repository with a headless agent,
# with or without the skill installed, and saves the transcript and diff for grading.
#
# Usage:  evals/run.sh <scenario-id> [--agent claude|codex] [--without-skill] [--dry-run]
# Output: evals/results/<scenario>-<agent>-<with|without>-<timestamp>/
#         prompt.txt, transcript.txt (raw), transcript.md (readable, claude only), diff.patch
# Needs:  bash, git, python3, and the chosen agent CLI logged in. Agent runs cost tokens.
#
# Grade by giving a judge model: the scenario's expectations (evals.json), the
# answer key (graders/), transcript.txt and diff.patch.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENARIO="${1:-}"; [ -n "$SCENARIO" ] || { sed -n '2,10p' "$0"; exit 2; }
shift
AGENT="claude"; WITH_SKILL=1; DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT="$2"; shift ;;
    --without-skill) WITH_SKILL=0 ;;
    --dry-run) DRY_RUN=1 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

read_field() {
  python3 -I -c "
import json, sys
d = json.load(open(sys.argv[1]))
s = next((s for s in d['scenarios'] if s['id'] == sys.argv[2]), None)
if s is None: sys.exit('unknown scenario: ' + sys.argv[2])
print(s[sys.argv[3]])" "$ROOT/evals/evals.json" "$SCENARIO" "$1"
}
PROMPT="$(read_field prompt)"
FIXTURE="$ROOT/evals/$(read_field fixture)"

label="$([ $WITH_SKILL -eq 1 ] && echo with || echo without)"
OUT="$ROOT/evals/results/$SCENARIO-$AGENT-$label-$(date +%Y%m%d-%H%M%S)-$$"
WORK="$(mktemp -d)/repo"

cp -R "$FIXTURE" "$WORK"
git -C "$WORK" init -q && git -C "$WORK" add -A && git -C "$WORK" -c user.email=eval@local -c user.name=eval commit -qm fixture
if [ $WITH_SKILL -eq 1 ]; then
  target="$([ "$AGENT" = claude ] && echo claude || echo codex)"
  "$ROOT/install.sh" --target "$target" --scope project --project "$WORK" >/dev/null
  git -C "$WORK" add -A && git -C "$WORK" -c user.email=eval@local -c user.name=eval commit -qm "install skill"
fi

BASE="$(git -C "$WORK" rev-parse HEAD)"   # diff against this even if the agent commits

case "$AGENT" in
  claude) CMD=(claude -p "$PROMPT" --permission-mode acceptEdits --allowedTools "Bash Read Edit Write Glob Grep Skill"
                --output-format stream-json --verbose) ;;
  codex)  CMD=(codex exec --full-auto "$PROMPT") ;;
  *) echo "unsupported agent: $AGENT" >&2; exit 2 ;;
esac

echo "scenario: $SCENARIO   agent: $AGENT   skill: $label"
echo "workdir:  $WORK"
echo "base:     $BASE"
if [ $DRY_RUN -eq 1 ]; then echo "would run: ${CMD[*]}"; exit 0; fi

mkdir -p "$OUT"
printf '%s\n' "$PROMPT" > "$OUT/prompt.txt"
(cd "$WORK" && "${CMD[@]}") > "$OUT/transcript.txt" 2>&1 || echo "agent exited non-zero (see transcript)"
[ "$AGENT" = claude ] && python3 -I "$ROOT/evals/summarize_transcript.py" "$OUT/transcript.txt" > "$OUT/transcript.md"
git -C "$WORK" add -A
git -C "$WORK" diff --cached "$BASE" -- . ':(exclude).claude' ':(exclude).agents' ':(exclude)CLAUDE.md' \
  ':(exclude)AGENTS.md' ':(exclude).hypothesis' ':(exclude).coverage' ':(exclude)*_cache' > "$OUT/diff.patch"
printf '%s\n' "$WORK" > "$OUT/workdir.txt"
echo "results:  $OUT"
