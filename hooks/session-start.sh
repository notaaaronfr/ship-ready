#!/usr/bin/env bash
# Claude Code plugin hook: prints the ship-ready guardrails at session start, so the
# critical rules apply even when the skill itself isn't loaded for a request.
# Skips silently when install.sh already put the guardrails in a CLAUDE.md file.
#
# Usage: run by Claude Code via hooks/hooks.json (needs CLAUDE_PLUGIN_ROOT).

set -u
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SKILL_DIR="$ROOT/skills/ship-ready"
MARKER="<!-- BEGIN ship-ready -->"

for f in "${CLAUDE_PROJECT_DIR:-$PWD}/CLAUDE.md" "$HOME/.claude/CLAUDE.md"; do
  if [ -f "$f" ] && grep -qF "$MARKER" "$f"; then exit 0; fi
done
[ -f "$SKILL_DIR/guardrails.md" ] || exit 0

sed -e "s|{{VERSION}}|$(cat "$ROOT/VERSION" 2>/dev/null || echo "?")|g" \
    -e "s|{{SKILL_DIR}}|$SKILL_DIR|g" "$SKILL_DIR/guardrails.md"
