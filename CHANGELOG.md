# Changelog

All notable changes to this project are documented here. Versions follow
[Semantic Versioning](https://semver.org/).

## [2.2.0] — 2026-10-09

### Changed
- **Renamed to `ship-ready`** (was `enterprise-code-quality`). Invoke with `/ship-ready` or `$ship-ready`.
  Re-running `./install.sh` removes installs, Gemini commands and guardrail blocks made
  under the old name, including symlinks left dangling by the rename.

### Added
- MIT license.
- Fixes for gaps found by blind-graded evals (with skill 0.79 vs 0.46 without):
  - final verification pass: every reported metric needs fresh output, or it says "not measured"
  - verdict rule applied mechanically
  - oracle test required for any algorithm rewrite
  - behavior-change audit over edge-case input classes
  - generated CI and Makefile must be run once
  - rationalizations for loosened assertions, stale lint numbers, and manual mutants passed off as a score

## [2.1.0] — 2026-10-09

Found by running the evals: with v2.0 installed, Claude Code never activated the skill for
"quick cleanup, don't bother with tests" or "use package X". In those runs it silently
changed `find_vip_customers` ordering without running tests, and ran `pip install` on a
non-existent package name. Agents load a skill only when the request matches its
description, so the rules that matter most must not depend on activation.

### Added
- **Always-on guardrails** (`guardrails.md`): five rules installed as a marked block in each
  agent's instruction file (CLAUDE.md, AGENTS.md, GEMINI.md, copilot-instructions.md):
  verify dependencies before installing, tests before and after, no silent behavior
  changes, always flag P0 risks, use the skill for cleanup-type requests. Opt out with `--no-guardrails`.
- **Quick mode** in SKILL.md: a 6-step path for small or urgent changes. Urgency changes the depth, never the gates.
- Eval runner records the full tool trace (`transcript.md`) for grading.

### Changed
- Description rewritten to trigger on quick, time-pressured and readability-only cleanups.
- The single-file bundle starts with the guardrails.

## [2.0.0] — 2026-10-09

### Changed (breaking)
- **Install locations follow current agent docs.** Codex, Copilot and Gemini now install
  to the shared Agent Skills location (`~/.agents/skills`, `.agents/skills`) instead of
  `~/.codex/skills`, `.codex/skills`, `~/.copilot/skills`, `.github/skills` and
  `.gemini/skills`. Re-running the installer removes v1.0 copies, which agents would
  otherwise list twice.
- Dropped the Copilot `.prompt.md` file (skills already provide `/enterprise-code-quality`,
  and VS Code is deprecating prompt files for agent sessions) and the `GEMINI.md` block
  (Gemini loads skills natively).

### Added
- **Evidence gates:** the Iron Law, a claim → required-evidence table, a rationalization
  table and red-flag words.
- **Phase 1, lock behavior:** characterization tests with a sensitivity proof.
- **Assessment upgrades:** spec-conformance check, "find the skeletons", domain risk
  questions, falsifiable finding format, confidence levels, a do-not-flag list,
  size-adaptive depth (S/M/L) and hotspot prioritization.
- **Optimization discipline:** MEASURE → IDENTIFY → FIX → VERIFY → GUARD, keep/revert
  rule (neutral = revert), oracle tests, and a ledger of reverted attempts.
- **QA upgrades:** Google test sizes, the property strength ladder with tautology and
  vacuity checks, mutation-survivor triage, a test-smell catalog, cognitive complexity
  and duplication gates.
- `references/security.md`: OWASP Top 10:2025, CWE Top 25 2025, OWASP LLM / Agentic
  risks, supply chain, source → sink method.
- `references/report-format.md`: Markdown and JSON report, maturity scorecard, coverage
  attestation, verdict rule.
- Scripts: `hotspots.sh`, `verify_package.sh` (PyPI, npm, crates.io, Go);
  `quality_gate.sh` gains `--json`, complexity and duplication checks.
- Templates: CI pinned by commit SHA with least-privilege permissions and PR-scoped
  mutation testing; `pre-commit-config.yaml`.
- Spec-compliant frontmatter (`compatibility`, `metadata.version`).
- `evals/`: planted-defect fixture with decoy, 5 scenarios, 20 trigger queries, runner, answer key.
- `tools/validate_skill.sh`, `tests/test_install.sh` (24 cases), repository CI on Linux and macOS.

## [1.0.0] — 2026-10-09

### Added
- `enterprise-code-quality` skill: six-phase workflow with five reference guides, a
  stack-detecting quality-gate script, and README / ADR / PR / CI / Makefile templates.
- `install.sh` for Claude Code, Codex, GitHub Copilot, Gemini CLI, AGENTS.md agents and a
  Markdown bundle; user and project scopes; `--status`, `--uninstall`, `--dry-run`.
