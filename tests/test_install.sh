#!/usr/bin/env bash
# Integration tests for install.sh. Runs in a throwaway HOME and project, so
# nothing on the real machine is touched.
#
# Usage: tests/test_install.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="ship-ready"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
REPO="$TMP/repo"
mkdir -p "$HOME" "$REPO"

passed=0; failed=0
check() {   # check <description> <command...>
  if "${@:2}" >/dev/null 2>&1; then passed=$((passed + 1)); printf 'ok    %s\n' "$1"
  else failed=$((failed + 1)); printf 'FAIL  %s\n' "$1"; fi
}
install() { "$ROOT/install.sh" "$@" >/dev/null 2>&1; }
not() { ! "$@"; }

# --- user scope
install --all
check "user: claude skill linked"            test -L "$HOME/.claude/skills/$SKILL"
check "user: shared skill linked"            test -L "$HOME/.agents/skills/$SKILL"
check "user: gemini command written"         test -f "$HOME/.gemini/commands/$SKILL.toml"
check "user: no legacy codex location"       not test -e "$HOME/.codex/skills/$SKILL"
check "user: SKILL.md reachable via link"    test -f "$HOME/.agents/skills/$SKILL/SKILL.md"
check "user: claude guardrails"              grep -q "verify_package.sh" "$HOME/.claude/CLAUDE.md"
check "user: codex guardrails"               grep -q "verify_package.sh" "$HOME/.codex/AGENTS.md"
check "user: copilot guardrails"             grep -q "verify_package.sh" "$HOME/.copilot/copilot-instructions.md"
check "user: gemini guardrails"              grep -q "verify_package.sh" "$HOME/.gemini/GEMINI.md"
check "user: guardrail paths are absolute"   grep -q "$HOME/.claude/skills/$SKILL/scripts" "$HOME/.claude/CLAUDE.md"

# --- project scope keeps existing AGENTS.md content and is idempotent
printf '# Team rules\n\nUse tabs.\n' > "$REPO/AGENTS.md"
install --all --scope project --project "$REPO"
install --all --scope project --project "$REPO"
check "project: claude skill copied"          test -f "$REPO/.claude/skills/$SKILL/SKILL.md"
check "project: shared skill copied"          test -f "$REPO/.agents/skills/$SKILL/SKILL.md"
check "project: copies are not symlinks"      not test -L "$REPO/.agents/skills/$SKILL"
check "project: version stamp written"        test -f "$REPO/.agents/skills/$SKILL/.version"
check "project: AGENTS.md keeps user content" grep -q "Use tabs." "$REPO/AGENTS.md"
check "project: exactly one managed block"    test "$(grep -c "BEGIN $SKILL" "$REPO/AGENTS.md")" = 1
check "project: AGENTS.md has guardrails"     grep -q "Verify before you install" "$REPO/AGENTS.md"
check "project: CLAUDE.md has guardrails"     grep -q "Verify before you install" "$REPO/CLAUDE.md"
check "project: guardrail paths are relative" grep -q '`bash .claude/skills/' "$REPO/CLAUDE.md"
check "project: no unreplaced placeholders"   not grep -q "{{" "$REPO/CLAUDE.md" "$REPO/AGENTS.md" "$REPO/GEMINI.md"

# --- --no-guardrails installs the skill only
NG="$TMP/noguard"; mkdir -p "$NG"
install --target claude --scope project --project "$NG" --no-guardrails
check "no-guardrails: skill installed"        test -f "$NG/.claude/skills/$SKILL/SKILL.md"
check "no-guardrails: no CLAUDE.md written"   not test -e "$NG/CLAUDE.md"

# --- migration from v1.0 layout
mkdir -p "$HOME/.codex/skills" "$REPO/.github/skills"
cp -R "$ROOT/skills/$SKILL" "$HOME/.codex/skills/"
cp -R "$ROOT/skills/$SKILL" "$REPO/.github/skills/"
install --target codex
install --target copilot --scope project --project "$REPO"
check "migration: removes ~/.codex copy"      not test -e "$HOME/.codex/skills/$SKILL"
check "migration: removes .github/skills copy" not test -e "$REPO/.github/skills/$SKILL"

# --- migration from the old name (enterprise-code-quality)
OLD=enterprise-code-quality; OR="$TMP/oldrepo"; mkdir -p "$OR/.claude/skills/$OLD" "$HOME/.agents/skills"
printf -- '---\nname: %s\n---\n' "$OLD" > "$OR/.claude/skills/$OLD/SKILL.md"
printf '# Ours\n\n<!-- BEGIN %s -->\nold rules\n<!-- END %s -->\n' "$OLD" "$OLD" > "$OR/CLAUDE.md"
ln -s "/nonexistent/skills/$OLD" "$HOME/.agents/skills/$OLD"          # dangling link left by the rename
install --target claude --scope project --project "$OR"
install --target codex
check "rename: old project skill removed"     not test -e "$OR/.claude/skills/$OLD"
check "rename: old guardrail block removed"   not grep -q "BEGIN $OLD" "$OR/CLAUDE.md"
check "rename: user content kept"             grep -q "# Ours" "$OR/CLAUDE.md"
check "rename: new guardrails added"          grep -q "BEGIN $SKILL" "$OR/CLAUDE.md"
check "rename: dangling old link removed"     not test -L "$HOME/.agents/skills/$OLD"

# --- safety
mkdir -p "$HOME/.claude/skills"; rm -rf "$HOME/.claude/skills/$SKILL"
mkdir -p "$HOME/.claude/skills/$SKILL"; echo "name: someone-else" > "$HOME/.claude/skills/$SKILL/SKILL.md"
check "safety: refuses to overwrite foreign skill" not install --target claude
check "safety: foreign skill untouched"       grep -q someone-else "$HOME/.claude/skills/$SKILL/SKILL.md"
rm -rf "$HOME/.claude/skills/$SKILL"
check "args: unknown target rejected"         not install --target nope
check "args: --link with project rejected"    not install --link --scope project --project "$REPO" --target claude
check "dry-run: changes nothing"              bash -c "'$ROOT/install.sh' --target claude --dry-run >/dev/null && ! test -e '$HOME/.claude/skills/$SKILL'"

# --- bundle
install --target bundle --out "$TMP/dist"
check "bundle: written"                       test -s "$TMP/dist/$SKILL.md"
check "bundle: includes references"           grep -q "references/security.md" "$TMP/dist/$SKILL.md"
check "bundle: starts with guardrails"        grep -q "Verify before you install" "$TMP/dist/$SKILL.md"
check "bundle: no frontmatter"                not grep -q "^name: $SKILL" "$TMP/dist/$SKILL.md"

# --- uninstall leaves no trace and restores AGENTS.md
install --all --uninstall
install --all --uninstall --scope project --project "$REPO"
check "uninstall: user home empty"            test -z "$(find "$HOME" -mindepth 1 -not -path "$HOME/.claude" -not -path "$HOME/.claude/skills")"
check "uninstall: project has only AGENTS.md" test "$(cd "$REPO" && find . -mindepth 1)" = "./AGENTS.md"
check "uninstall: AGENTS.md restored"         test "$(cat "$REPO/AGENTS.md")" = "$(printf '# Team rules\n\nUse tabs.')"

echo "---"
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
