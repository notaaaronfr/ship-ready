# Changelog

All notable changes to this project are documented here. Versions follow
[Semantic Versioning](https://semver.org/).

## [2.4.1] — 2026-10-09

### Fixed
- **Quality gate missed pip-installed tools.** Agents install linters with `pip install`, which
  makes them runnable as `python3 -m ruff` but not always as `ruff` on PATH. The gate reported
  NO_CHECKS_RAN, agents abandoned it for ad-hoc commands, and so never reached `verdict.py`.
  This happened in all three v2.4 eval runs. The gate now falls back to `python3 -m <tool>`, and
  the skill says to install tools and re-run the gate rather than bypass it.

## [2.4.0] — 2026-10-09

In every v2.3 run, the final report was the weakest part: two of three said READY despite skipped
gates, and run 1 claimed "all quality gates passing" while its formatting and type checks failed.

### Added
- **`scripts/verdict.py`** computes READY / READY_WITH_CONDITIONS / NOT_READY from the gate JSON
  and open findings. The agent must copy it verbatim and may not upgrade it.
  `tests/test_verdict.sh` (11 cases) runs in CI.
- **New validation is a behavior change:** inputs the original accepted are run through
  `tests/_original.py` and the new code, and every newly rejected input must be disclosed.
- Baseline must be recorded before any file is created or edited; unmeasured values say "not measured".
- README "See it work" section with unedited output from the eval runs.

## [2.3.0] — 2026-10-09

Rules that described an outcome ("prove equivalence", "replace weak tests") were skipped
in graded runs, so each is now a concrete step the agent can't do halfway.

**Eval result:** full-harden mean rose from 0.77 (v2.1/v2.2, 2 runs) to 0.83 (3 runs: 0.92,
0.79, 0.79); without the skill, 0.46. Weak tests were fixed in 3/3 runs and mutations were
logged in 3/3. Oracle tests were present in every run that rewrote the function (2/3).

### Changed
- **Oracle tests:** before rewriting a function, copy the original verbatim into
  `tests/_original.py` and compare old and new on generated inputs. Intended changes are
  asserted as explicit exceptions.
- **Weak tests:** every weak test found in assessment is rewritten or deleted, using a grep
  sweep. "Backwards compatibility" is not a reason to keep one.
- Eval runner: unique result folders per process, so parallel runs don't collide.
- **Mutation claims:** each manual mutant runs as its own command and is logged in
  `.quality/mutations.md`. The report may list only logged mutants, and every report claim
  must point to command output.

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
