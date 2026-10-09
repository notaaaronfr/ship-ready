#!/usr/bin/env bash
# Validates a skill directory against the Agent Skills specification
# (agentskills.io) and this repository's authoring rules.
#
# Usage: tools/validate_skill.sh [skill_dir=skills/ship-ready]
# Exit:  0 valid · 1 errors found

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${1:-$ROOT/skills/ship-ready}"
SKILL="$DIR/SKILL.md"
errors=0; warnings=0
err()  { printf 'ERROR  %s\n' "$*"; errors=$((errors + 1)); }
warn() { printf 'WARN   %s\n' "$*"; warnings=$((warnings + 1)); }
ok()   { printf 'ok     %s\n' "$*"; }

[ -f "$SKILL" ] || { err "missing $SKILL"; exit 1; }
[ "$(head -n 1 "$SKILL")" = "---" ] || err "SKILL.md must start with '---' frontmatter"

frontmatter="$(awk 'NR == 1 { next } $0 == "---" { exit } { print }' "$SKILL")"
body_lines="$(awk 'NR == 1 { next } fm == 0 && $0 == "---" { fm = 1; next } fm { n++ } END { print n + 0 }' "$SKILL")"
field() { printf '%s\n' "$frontmatter" | sed -n "s/^$1: *//p" | head -n 1; }

# Top-level keys: the spec allows only these (claude.ai and the API reject others).
for key in $(printf '%s\n' "$frontmatter" | grep -oE '^[a-zA-Z_-]+:' | tr -d ':'); do
  case "$key" in
    name|description|license|compatibility|metadata|allowed-tools) ;;
    *) err "frontmatter key '$key' is not in the Agent Skills spec" ;;
  esac
done

name="$(field name)"
if printf '%s' "$name" | grep -qE '^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$' && ! printf '%s' "$name" | grep -q -- '--'; then
  ok "name '$name' format"
else err "name '$name' must be 1-64 chars of a-z, 0-9, '-', not starting/ending with '-' or containing '--'"; fi
[ "$name" = "$(basename "$DIR")" ] && ok "name matches directory" || err "name '$name' must match directory '$(basename "$DIR")'"
printf '%s' "$name" | grep -qiE 'claude|anthropic' && err "name must not contain 'claude' or 'anthropic'"

desc="$(field description)"
dlen=${#desc}
if [ "$dlen" -ge 1 ] && [ "$dlen" -le 1024 ]; then ok "description length $dlen/1024"; else err "description length $dlen (must be 1-1024)"; fi
printf '%s' "$desc" | grep -q '[<>]' && err "description must not contain XML tags or angle brackets"
printf '%s' "$desc" | grep -qiE '\bUse (when|whenever)\b' && ok "description says when to use it" || warn "description should include 'Use when ...' triggers"
printf '%s' "$desc" | grep -qE '^(I |You )' && err "description must be third person"

compat="$(field compatibility)"
[ ${#compat} -le 500 ] || err "compatibility is ${#compat} chars (max 500)"

[ "$body_lines" -lt 500 ] && ok "SKILL.md body $body_lines lines (< 500)" || err "SKILL.md body is $body_lines lines (keep under 500; move detail to references/)"

meta_version="$(printf '%s\n' "$frontmatter" | sed -n 's/^ *version: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/p' | head -n 1)"
if [ -f "$ROOT/VERSION" ]; then
  [ "$meta_version" = "$(cat "$ROOT/VERSION")" ] && ok "metadata.version matches VERSION ($meta_version)" \
    || err "metadata.version '$meta_version' differs from VERSION '$(cat "$ROOT/VERSION")'"
fi

# Plugin manifests (Agent Plugins / Copilot, Claude Code) must carry the same version.
for manifest in "$ROOT/plugin.json" "$ROOT/.claude-plugin/plugin.json" "$ROOT/.claude-plugin/marketplace.json"; do
  [ -f "$manifest" ] || continue
  mv="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('version') or d.get('plugins',[{}])[0].get('version',''))" "$manifest" 2>/dev/null)"
  if [ "$mv" = "$(cat "$ROOT/VERSION")" ]; then ok "$(basename "$manifest") version $mv"
  else err "$(basename "$manifest") version '$mv' differs from VERSION"; fi
done

# Every relative path mentioned in SKILL.md must exist; references are one level deep.
for ref in $(grep -oE '(references|scripts|templates)/[A-Za-z0-9_.-]+' "$SKILL" | sort -u); do
  [ -e "$DIR/$ref" ] || err "SKILL.md references missing file $ref"
done
ok "all referenced files exist"

for f in "$DIR"/references/*.md; do
  [ -e "$f" ] || continue
  lines=$(wc -l < "$f" | tr -d ' ')
  if [ "$lines" -gt 100 ] && ! grep -q '^## Contents' "$f"; then
    warn "$(basename "$f") has $lines lines but no '## Contents' table of contents"
  fi
  grep -oE '\]\((references/[^)]+)\)' "$f" >/dev/null && warn "$(basename "$f") links deeper into references/ (keep one level)"
done

for s in "$DIR"/scripts/*; do
  [ -e "$s" ] || continue
  [ -x "$s" ] || err "$(basename "$s") is not executable"
  case "$s" in *.sh) bash -n "$s" || err "$(basename "$s") has a syntax error" ;; esac
  sed -n '2,4p' "$s" | grep -qE '^(#|""")' || warn "$(basename "$s") lacks a usage header comment"
done

grep -nE '\\[A-Za-z]+\\' "$SKILL" >/dev/null && warn "SKILL.md may contain Windows-style paths"

echo "---"
echo "$errors error(s), $warnings warning(s)"
[ "$errors" -eq 0 ]
