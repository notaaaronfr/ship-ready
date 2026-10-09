#!/usr/bin/env bash
# Installs the ship-ready skill into one or more AI coding agents.
#
# Agents converge on two skill locations, so the skill is installed at most twice:
#   .claude/skills   Claude Code (reads only this location)
#   .agents/skills   OpenAI Codex, GitHub Copilot (CLI + VS Code), Gemini CLI /
#                    Antigravity, and other tools following the Agent Skills spec
# plus always-on guardrails: a short managed block in each agent's instruction
# file (CLAUDE.md, AGENTS.md, GEMINI.md, copilot-instructions.md). Agents load a
# skill only when a request matches its description; the guardrails make the
# critical rules apply to every request. Also: a Gemini /command and a
# single-file Markdown bundle.
#
# Run with -h for usage. Compatible with macOS bash 3.2 and Linux bash 4+.

set -euo pipefail

SKILL_NAME="ship-ready"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$REPO_DIR/skills/$SKILL_NAME"
VERSION="$(cat "$REPO_DIR/VERSION")"
MARK_BEGIN="<!-- BEGIN $SKILL_NAME -->"
MARK_END="<!-- END $SKILL_NAME -->"
ALL_TARGETS="claude codex copilot gemini agents"
OLD_NAMES="enterprise-code-quality"   # earlier names of this skill, removed on install

SCOPE="user"
PROJECT_DIR="$PWD"
MODE="auto"            # auto | copy | link
ACTION="install"       # install | uninstall | status
DRY_RUN=0
GUARDRAILS=1
TARGETS=""
OUT_DIR="$REPO_DIR/dist"

usage() {
  cat <<EOF
$SKILL_NAME installer v$VERSION

Usage: ./install.sh [options] --target <name>[,<name>...] | --all

Targets                                  user scope            project scope
  claude    Claude Code                  ~/.claude/skills      .claude/skills
  codex     OpenAI Codex (CLI, IDE)      ~/.agents/skills      .agents/skills
  copilot   GitHub Copilot (CLI, VS Code)~/.agents/skills      .agents/skills
  gemini    Gemini CLI / Antigravity     ~/.agents/skills      .agents/skills   + /$SKILL_NAME command
  agents    Any other agent              ~/.agents/skills      .agents/skills   + AGENTS.md pointer
  bundle    Single editable Markdown     dist/$SKILL_NAME.md
  --all     Every target except bundle

  codex, copilot, gemini and agents share one .agents/skills install.

Always-on guardrails (skip with --no-guardrails)
  claude    ~/.claude/CLAUDE.md                  CLAUDE.md
  codex     ~/.codex/AGENTS.md                   AGENTS.md
  copilot   ~/.copilot/copilot-instructions.md   AGENTS.md
  gemini    ~/.gemini/GEMINI.md                  GEMINI.md
  agents    -                                    AGENTS.md
  Each is a marked block; the rest of the file is never touched.

Options:
  --scope user|project   Install for you (default) or into a repository for the whole team
  --project DIR          Repository to install into (default: current directory)
  --copy                 Always copy files (no symlinks)
  --link                 Symlink (user scope only), so 'git pull' here updates the skill
  --no-guardrails        Install the skill only; skip the always-on instruction blocks
  --out DIR              Output directory for the bundle target (default: dist/)
  --uninstall            Remove the skill from the selected targets
  --status               Show where the skill is installed
  --dry-run              Print what would change without touching anything
  -h, --help             Show this help

Examples:
  ./install.sh --all                                   # every agent, for you
  ./install.sh --target claude,copilot --scope project --project ~/code/api
  ./install.sh --target bundle                         # dist/$SKILL_NAME.md
  ./install.sh --all --uninstall
EOF
}

die()   { printf 'error: %s\n' "$*" >&2; exit 1; }
log()   { printf '  %s\n' "$*"; }
head_() { printf '\n▸ %s\n' "$*"; }
run()   { if [ "$DRY_RUN" -eq 1 ]; then log "[dry-run] $*"; else "$@"; fi; }
has_target() { case " $TARGETS " in *" $1 "*) return 0 ;; esac; return 1; }

# ---------------------------------------------------------------- arguments

while [ $# -gt 0 ]; do
  case "$1" in
    --target|-t) [ $# -ge 2 ] || die "--target needs a value"
                 TARGETS="$TARGETS $(printf '%s' "$2" | tr ',' ' ')"; shift ;;
    --all)       TARGETS="$TARGETS $ALL_TARGETS" ;;
    --scope)     [ $# -ge 2 ] || die "--scope needs a value"; SCOPE="$2"; shift ;;
    --project)   [ $# -ge 2 ] || die "--project needs a value"; PROJECT_DIR="$2"; shift ;;
    --copy)      MODE="copy" ;;
    --link)      MODE="link" ;;
    --no-guardrails) GUARDRAILS=0 ;;
    --out)       [ $# -ge 2 ] || die "--out needs a value"; OUT_DIR="$2"; shift ;;
    --uninstall) ACTION="uninstall" ;;
    --status)    ACTION="status" ;;
    --dry-run)   DRY_RUN=1 ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "unknown option: $1 (see --help)" ;;
  esac
  shift
done

case "$SCOPE" in user|project) ;; *) die "--scope must be 'user' or 'project'" ;; esac
[ -f "$SKILL_SRC/SKILL.md" ] || die "skill source not found at $SKILL_SRC"
[ "$ACTION" = "status" ] && [ -z "${TARGETS// /}" ] && TARGETS="$ALL_TARGETS bundle"
[ -n "${TARGETS// /}" ] || { usage; exit 1; }
for t in $TARGETS; do
  case " $ALL_TARGETS bundle " in *" $t "*) ;; *) die "unknown target: $t (see --help)" ;; esac
done
[ "$MODE" = "link" ] && [ "$SCOPE" = "project" ] && die "--link is only valid with --scope user"
if [ "$SCOPE" = "project" ]; then
  [ -d "$PROJECT_DIR" ] || die "project directory not found: $PROJECT_DIR"
  PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
fi

# Resolves a location for the current scope: scoped <user_path> <project_relative_path>
scoped() {
  if [ "$SCOPE" = "user" ]; then printf '%s' "$1"; else printf '%s/%s' "$PROJECT_DIR" "$2"; fi
}

CLAUDE_DIR="$(scoped "$HOME/.claude/skills" ".claude/skills")"
SHARED_DIR="$(scoped "$HOME/.agents/skills" ".agents/skills")"
GEMINI_CMD="$(scoped "$HOME/.gemini/commands" ".gemini/commands")/$SKILL_NAME.toml"

# Locations used by v1.0.0, cleaned up on install and uninstall. Agents read
# both old and new paths and do not de-duplicate, so stale copies show twice.
LEGACY_SKILL_DIRS="$(scoped "${CODEX_HOME:-$HOME/.codex}/skills" ".codex/skills")
$(scoped "$HOME/.copilot/skills" ".github/skills")
$(scoped "$HOME/.gemini/skills" ".gemini/skills")"
LEGACY_PROMPT="$PROJECT_DIR/.github/prompts/$SKILL_NAME.prompt.md"
LEGACY_GEMINI_MD="$(scoped "$HOME/.gemini/GEMINI.md" "GEMINI.md")"

# ---------------------------------------------------------------- helpers

# Symlinks only make sense on one person's machine. Repositories get real
# files so the team can commit them.
use_link() {
  case "$MODE" in
    link) return 0 ;;
    copy) return 1 ;;
    auto) [ "$SCOPE" = "user" ] ;;
  esac
}

# True if $1 is a skill directory (or link) that this installer created.
is_ours() {
  [ -L "$1" ] && [ "$(readlink "$1")" = "$SKILL_SRC" ] && return 0
  [ -f "$1/SKILL.md" ] && grep -q "^name: $SKILL_NAME\$" "$1/SKILL.md"
}

# Removes now-empty parent directories, stopping at the home or project directory.
prune_empty() {
  local dir="$1"
  [ "$DRY_RUN" -eq 1 ] && return 0
  while [ "$dir" != "$HOME" ] && [ "$dir" != "$PROJECT_DIR" ] && [ "$dir" != "/" ]; do
    rmdir "$dir" 2>/dev/null || return 0
    dir="$(dirname "$dir")"
  done
}

place_skill() {   # place_skill <skills_dir>
  local dest="$1/$SKILL_NAME"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    is_ours "$dest" || die "$dest exists and was not created by this installer; refusing to overwrite"
    run rm -rf "$dest"
  fi
  run mkdir -p "$1"
  if use_link; then
    run ln -s "$SKILL_SRC" "$dest"
    log "linked   $dest -> $SKILL_SRC"
  else
    run cp -R "$SKILL_SRC" "$dest"
    [ "$DRY_RUN" -eq 1 ] || printf '%s\n' "$VERSION" > "$dest/.version"
    log "copied   $dest (v$VERSION)"
  fi
}

remove_skill() {  # remove_skill <skills_dir>
  local dest="$1/$SKILL_NAME"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    is_ours "$dest" || die "$dest was not created by this installer; refusing to delete"
    run rm -rf "$dest"
    log "removed  $dest"
    prune_empty "$1"
  fi
}

remove_file() {
  if [ -f "$1" ]; then run rm -f "$1"; log "removed  $1"; prune_empty "$(dirname "$1")"; fi
}

write_file() {    # write_file <path> <content>
  if [ "$DRY_RUN" -eq 1 ]; then log "[dry-run] write $1"; return; fi
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" > "$1"
  log "wrote    $1"
}

# Prints <file> without the managed block and without trailing blank lines.
strip_block() {
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    skip    { next }
    { lines[++n] = $0; if ($0 != "") last = n }
    END     { for (i = 1; i <= last; i++) print lines[i] }
  ' "$1"
}

# Adds or replaces this skill's managed block in a shared Markdown file,
# leaving everything else in the file untouched.
upsert_block() {
  local file="$1" body="$2" kept=""
  if [ "$DRY_RUN" -eq 1 ]; then log "[dry-run] update managed block in $file"; return; fi
  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] && kept="$(strip_block "$file")"
  {
    if [ -n "$kept" ]; then printf '%s\n\n' "$kept"; fi
    printf '%s\n%s\n%s\n' "$MARK_BEGIN" "$body" "$MARK_END"
  } > "$file"
  log "updated  $file (managed block)"
}

remove_block() {
  local file="$1" kept
  [ -f "$file" ] && grep -qF "$MARK_BEGIN" "$file" || return 0
  if [ "$DRY_RUN" -eq 1 ]; then log "[dry-run] remove managed block from $file"; return; fi
  kept="$(strip_block "$file")"
  if [ -z "$kept" ]; then
    rm -f "$file"; log "removed  $file (contained only our block)"; prune_empty "$(dirname "$file")"
  else
    printf '%s\n' "$kept" > "$file"; log "cleaned  $file (managed block removed)"
  fi
}

status_line() {   # status_line <skills_dir>
  local dest="$1/$SKILL_NAME" state
  if [ -L "$dest" ]; then state="linked -> $(readlink "$dest")"
  elif [ -f "$dest/.version" ]; then state="v$(cat "$dest/.version") (copy)"
  elif [ -d "$dest" ]; then state="installed (unknown version)"
  else state="not installed"; fi
  log "$dest: $state"
}

# SKILL.md without its YAML frontmatter.
skill_body() {
  awk 'NR == 1 && $0 == "---" { fm = 1; next } fm && $0 == "---" { fm = 0; next } !fm' "$SKILL_SRC/SKILL.md"
}

cleanup_legacy() {
  local found=0 dir
  while IFS= read -r dir; do
    if is_ours "$dir/$SKILL_NAME" 2>/dev/null; then
      [ $found -eq 1 ] || head_ "Removing v1.0 locations (prevents duplicate skills)"; found=1
      remove_skill "$dir"
    fi
  done <<EOF
$LEGACY_SKILL_DIRS
EOF
  if [ -f "$LEGACY_PROMPT" ] || { ! has_target gemini && [ -f "$LEGACY_GEMINI_MD" ] && grep -qF "$MARK_BEGIN" "$LEGACY_GEMINI_MD"; }; then
    [ $found -eq 1 ] || head_ "Removing v1.0 locations (prevents duplicate skills)"
    [ "$SCOPE" = "project" ] && remove_file "$LEGACY_PROMPT"
    has_target gemini || remove_block "$LEGACY_GEMINI_MD"   # otherwise replaced by the guardrails block
  fi
  return 0
}

# Removes installs made under an earlier name of this skill: skill folders
# (including symlinks left dangling by the rename), the Gemini command, and
# guardrail blocks in instruction files.
cleanup_renamed() {
  local old dir path saved_begin="$MARK_BEGIN" saved_end="$MARK_END" file
  for old in $OLD_NAMES; do
    while IFS= read -r dir; do
      [ -n "$dir" ] || continue
      path="$dir/$old"
      if [ -L "$path" ]; then
        case "$(readlink "$path")" in */skills/"$old") ;; *) continue ;; esac
      elif ! { [ -f "$path/SKILL.md" ] && grep -q "^name: $old\$" "$path/SKILL.md"; }; then
        continue
      fi
      run rm -rf "$path"; log "removed  $path (renamed to $SKILL_NAME)"; prune_empty "$dir"
    done <<DIRS
$CLAUDE_DIR
$SHARED_DIR
$LEGACY_SKILL_DIRS
DIRS
    remove_file_if_contains "$(dirname "$GEMINI_CMD")/$old.toml" "$old"
    MARK_BEGIN="<!-- BEGIN $old -->"; MARK_END="<!-- END $old -->"
    instruction_files | while IFS= read -r file; do remove_block "$file"; done
    MARK_BEGIN="$saved_begin"; MARK_END="$saved_end"
  done
  return 0
}

remove_file_if_contains() {   # remove_file_if_contains <file> <text>
  if [ -f "$1" ] && grep -qF "$2" "$1"; then remove_file "$1"; fi
}

# Every instruction file this installer may write for the current scope.
instruction_files() {
  if [ "$SCOPE" = "user" ]; then
    printf '%s\n' "$HOME/.claude/CLAUDE.md" "${CODEX_HOME:-$HOME/.codex}/AGENTS.md" \
      "$HOME/.copilot/copilot-instructions.md" "$HOME/.gemini/GEMINI.md"
  else
    printf '%s\n' "$PROJECT_DIR/CLAUDE.md" "$PROJECT_DIR/AGENTS.md" "$PROJECT_DIR/GEMINI.md"
  fi
}

# ---------------------------------------------------------------- actions

do_claude() {
  head_ "Claude Code"
  case "$ACTION" in
    install)   place_skill "$CLAUDE_DIR"
               log "use:     /$SKILL_NAME <path>, or ask \"make this enterprise grade\"" ;;
    uninstall) remove_skill "$CLAUDE_DIR" ;;
    status)    status_line "$CLAUDE_DIR" ;;
  esac
}

do_shared() {     # do_shared <space-separated agent labels>
  head_ "Agent Skills standard location ($1)"
  case "$ACTION" in
    install)
      place_skill "$SHARED_DIR"
      has_target codex   && log "codex:   \$$SKILL_NAME or /skills; restart Codex to load"
      has_target copilot && log "copilot: /$SKILL_NAME in Copilot CLI or VS Code agent mode"
      has_target gemini  && log "gemini:  activates automatically; /skills list to confirm"
      if [ "$SCOPE" = "project" ] && has_target copilot && has_target claude; then
        log "note:    Copilot also reads .claude/skills, so it may list this skill twice"
      fi ;;
    uninstall) remove_skill "$SHARED_DIR"
               log "note:    this location is shared by codex, copilot, gemini and agents" ;;
    status)    status_line "$SHARED_DIR" ;;
  esac
}

do_gemini_command() {
  head_ "Gemini CLI /$SKILL_NAME command"
  case "$ACTION" in
    install)
      write_file "$GEMINI_CMD" "description = \"Harden code to enterprise grade: refactor, optimize, QA, document (v$VERSION)\"
prompt = \"\"\"
Activate the $SKILL_NAME skill (installed in $SHARED_DIR/$SKILL_NAME)
and follow its workflow from Phase 0 on: {{args}}
\"\"\"" ;;
    uninstall) remove_file "$GEMINI_CMD" ;;
    status)    if [ -f "$GEMINI_CMD" ]; then log "$GEMINI_CMD: present"; else log "$GEMINI_CMD: not installed"; fi ;;
  esac
}

# Prints "instruction_file<TAB>skill_dir" for each selected target, one per line.
# Several agents can share one file (AGENTS.md); do_guardrails de-duplicates.
guardrail_files() {
  local claude_skill shared_skill
  if [ "$SCOPE" = "user" ]; then
    claude_skill="$CLAUDE_DIR/$SKILL_NAME"; shared_skill="$SHARED_DIR/$SKILL_NAME"
    has_target claude  && printf '%s\t%s\n' "$HOME/.claude/CLAUDE.md" "$claude_skill"
    has_target codex   && printf '%s\t%s\n' "${CODEX_HOME:-$HOME/.codex}/AGENTS.md" "$shared_skill"
    has_target copilot && printf '%s\t%s\n' "$HOME/.copilot/copilot-instructions.md" "$shared_skill"
    has_target gemini  && printf '%s\t%s\n' "$HOME/.gemini/GEMINI.md" "$shared_skill"
  else
    claude_skill=".claude/skills/$SKILL_NAME"; shared_skill=".agents/skills/$SKILL_NAME"
    has_target claude  && printf '%s\t%s\n' "$PROJECT_DIR/CLAUDE.md" "$claude_skill"
    has_target gemini  && printf '%s\t%s\n' "$PROJECT_DIR/GEMINI.md" "$shared_skill"
    if has_target codex || has_target copilot || has_target agents; then
      printf '%s\t%s\n' "$PROJECT_DIR/AGENTS.md" "$shared_skill"
    fi
  fi
  return 0
}

guardrails_text() {   # guardrails_text <skill_dir>
  sed -e "s|{{VERSION}}|$VERSION|g" -e "s|{{SKILL_DIR}}|$1|g" "$SKILL_SRC/guardrails.md"
}

do_guardrails() {
  local file dir tab
  tab="$(printf '\t')"
  head_ "Always-on guardrails"
  while IFS="$tab" read -r file dir; do
    [ -n "$file" ] || continue
    case "$ACTION" in
      install)   upsert_block "$file" "$(guardrails_text "$dir")" ;;
      uninstall) remove_block "$file" ;;
      status)    if [ -f "$file" ] && grep -qF "$MARK_BEGIN" "$file"; then log "$file: present"
                 else log "$file: not installed"; fi ;;
    esac
  done <<GUARDRAIL_FILES
$(guardrail_files | awk -F '\t' '!seen[$1]++')
GUARDRAIL_FILES
}

do_bundle() {
  local out="$OUT_DIR/$SKILL_NAME.md" body f
  head_ "Editable single-file bundle"
  case "$ACTION" in
    install)
      body="<!-- $SKILL_NAME v$VERSION. Generated by install.sh: edit skills/$SKILL_NAME, not this file. -->
$(guardrails_text "the $SKILL_NAME skill folder")

---
$(skill_body)"
      for f in "$SKILL_SRC"/references/*.md; do
        body="$body

---
<!-- references/$(basename "$f") -->
$(cat "$f")"
      done
      write_file "$out" "$body"
      log "use:     paste into any agent's rules or custom instructions, or attach to a chat" ;;
    uninstall) remove_file "$out" ;;
    status)    if [ -f "$out" ]; then log "$out: present"; else log "$out: not built"; fi ;;
  esac
}

# ---------------------------------------------------------------- main

printf '%s v%s: %s (scope: %s%s)\n' "$SKILL_NAME" "$VERSION" "$ACTION" "$SCOPE" \
  "$([ "$SCOPE" = "project" ] && printf ', %s' "$PROJECT_DIR")"

shared_labels=""
for t in codex copilot gemini agents; do has_target "$t" && shared_labels="$shared_labels${shared_labels:+, }$t"; done

[ "$ACTION" = "status" ] || { cleanup_legacy; cleanup_renamed; }
has_target claude      && do_claude
[ -n "$shared_labels" ] && do_shared "$shared_labels"
has_target gemini      && do_gemini_command
if [ "$GUARDRAILS" -eq 1 ] || [ "$ACTION" = "uninstall" ]; then
  for t in $ALL_TARGETS; do if has_target "$t"; then do_guardrails; break; fi; done
fi
has_target bundle      && do_bundle
printf '\nDone.\n'
