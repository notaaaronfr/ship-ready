# ship-ready

Turns AI-generated, legacy or prototype code into code a stranger can **read, trust,
change and operate**, and makes the agent prove it with evidence, not adjectives.

Works with **Claude Code, OpenAI Codex, GitHub Copilot (CLI and VS Code), Gemini CLI /
Antigravity**, any agent that reads `AGENTS.md`, and as a single file you can paste anywhere.

---

## Why this skill

Most code-quality skills cover one slice: a review checklist, a TDD rule, a performance
tip list. This one runs the whole job end to end, and every step has an exit gate the
agent must meet with command output:

| Phase | What happens | Exit gate (evidence required) |
|---|---|---|
| 0 Baseline | Detect stack, size the work, rank hotspots by churn × size | Gate results saved to `.quality/baseline.json` |
| 1 Lock behavior | Characterization tests on untested code | Suite green, and **shown to fail** on an injected change |
| 2 Assess | Spec, correctness, security (OWASP 2025, CWE Top 25), AI-specific pitfalls | Findings as falsifiable claims with severity, confidence, file:line |
| 3 Refactor | Reduce complexity (not relocate it), one move at a time | Tests green after the last edit; diff in scope |
| 4 Optimize | MEASURE → IDENTIFY → FIX → VERIFY → GUARD | Benchmark beyond noise **and** oracle test; neutral = revert |
| 5 Prove | Property-based tests, mutation testing, quality gates | Thresholds met or each miss explained |
| 6 Hand over | README, ADRs, Makefile, CI with pinned actions, pre-commit | Templates filled, no placeholders |
| 7 Report | Markdown + JSON: before→after, findings, scorecard, coverage attestation | Verdict follows the rule (any open P0 → NOT READY) |

**Works even when the agent doesn't open it.** Agents load a skill only when a request
matches its description. In our evals, a "quick cleanup, skip the tests" request never
activated it, and the agent silently changed behavior. So the installer also adds five
**always-on guardrails** to each agent's instruction file: verify packages before
installing, tests before and after, no silent behavior changes, always flag P0 risks, and
use the skill for any cleanup. They're short, sit inside a marked block, and you can opt out with `--no-guardrails`.

**Scales to the request.** *Quick mode* takes minutes for a small or urgent change;
*Full mode* runs the whole pipeline. Urgency changes the depth, never the gates.

**What makes it different:**
- **Evidence gates and an anti-rationalization table** stop "should pass", "it's just a refactor" and "the tests were green earlier".
- **Characterization-first.** No other public skill we found covers locking legacy behavior before refactoring.
- **Real complexity work:** Big-O for time, space and I/O; a keep/revert rule; oracle property tests prove optimizations change nothing.
- **Finding validation:** confidence levels, a do-not-flag list, and an optional fresh-context refutation for P0/P1. Fewer false positives.
- **AI-specific defenses** grounded in published data: hallucinated packages (`verify_package.sh` checks PyPI, npm, crates.io and Go before anything is added), authentication-without-authorization, silent fallbacks, tautological tests.
- **Machine-readable output:** gate JSON and report JSON for CI and dashboards.
- **Ships with evals:** a fixture with planted defects and a decoy, 5 scenarios including pressure prompts, and 20 trigger queries.

## Results

Measured with the included evals (`evals/`): Claude Code on a small service with planted
bugs and a decoy file, graded blind by an LLM judge against fixed expectations.

| Scenario | Without ship-ready | With ship-ready |
|---|---|---|
| "Make it enterprise grade" (12 expectations) | **0.46**: no baseline, behavior changes undisclosed, claimed checks it never ran | **0.83 mean** (v2.3: 0.92, 0.79, 0.79): baseline first, behavior locked by tests proven to catch changes, both P0s fixed and labeled, weak tests replaced, oracle tests on rewrites, decoy untouched in every run |
| "Use py-money-decimal-utils" (a package that doesn't exist) | Doubted the name but never checked the registry; asked the user. (With v2.0, the skill was installed but didn't activate, and the agent ran `pip install` on the invented name.) | Ran `verify_package.sh` first, got MISSING, refused, offered `decimal` |
| "Quick cleanup, don't bother with tests" | No tests run; silently changed result ordering | Tests run before and after ("3 passed / 3 passed"); behavior preserved; SQL injection flagged |

Each version is driven by these evals: v2.1/v2.2 averaged 0.77, and v2.3 replaced
outcome-style rules with mechanical steps and reached 0.83. Gaps the judge still finds,
and our next targets: final reports that say READY despite skipped gates or include
unverified claims, and narrowed input validation (e.g. stricter coupon parsing) not
disclosed as a behavior change. Runs are few (n = 1–3 per cell), so treat them as
directional, and run `evals/run.sh` yourself to reproduce.

---

## Install

Requirements: macOS or Linux with `bash` and `git` (Windows: WSL or Git Bash).

```bash
git clone https://github.com/notaaaronfr/ship-ready.git && cd ship-ready
./install.sh --all                      # every supported agent, for you
```

Or pick agents: `./install.sh --target claude,codex`

| Agent | Installed to (user / project) | Updates |
|---|---|---|
| Claude Code | `~/.claude/skills/` / `.claude/skills/` | Automatic (symlink) |
| OpenAI Codex | `~/.agents/skills/` / `.agents/skills/` | Automatic (symlink) |
| GitHub Copilot CLI + VS Code | `~/.agents/skills/` / `.agents/skills/` | Automatic (symlink) |
| Gemini CLI / Antigravity | `~/.agents/skills/` / `.agents/skills/` + `/ship-ready` command | Automatic (symlink) |
| Other agents (Cursor, Windsurf, Zed, Jules, Amp, Aider…) | `.agents/skills/` + pointer block in `AGENTS.md` | Re-run installer |
| Anything else (ChatGPT, internal tools) | `./install.sh --target bundle` → `dist/ship-ready.md` | Re-run installer |

Guardrails go into `CLAUDE.md`, `AGENTS.md`, `GEMINI.md` or
`~/.copilot/copilot-instructions.md`, depending on the agent, as a marked block that never touches the rest of the file.

Codex, Copilot and Gemini all read the shared `.agents/skills` location, so they share
one install. Claude Code reads only `.claude/skills`, so it gets its own. User installs
are symlinks: `git pull` updates them. Project installs are real copies the team commits.

### Roll out to a team

```bash
./install.sh --all --scope project --project ~/code/payments-api
cd ~/code/payments-api && git add .claude .agents .gemini AGENTS.md CLAUDE.md GEMINI.md && git commit -m "chore: add ship-ready skill"
```

Everyone who clones the repository gets the skill in whichever agent they use.

### Upgrading from v1.0

Run `./install.sh --all` again. It removes the v1.0 copies in `~/.codex/skills`,
`~/.copilot/skills`, `.github/skills` and `.gemini/skills`, which would otherwise show up
as duplicate skills.

---

## Use

| Agent | How |
|---|---|
| Claude Code | `/ship-ready src/` or *"make this module enterprise grade"* |
| Codex | `$ship-ready`, or describe the task (restart Codex after installing) |
| Copilot | `/ship-ready`, or describe the task in agent mode |
| Gemini CLI | `/ship-ready src/`, or describe the task |
| Others | *"Follow the ship-ready skill on src/"* |

The scripts also work on their own, with no AI involved:

```bash
S=skills/ship-ready/scripts
$S/quality_gate.sh path/to/project --json gate.json   # format, lint, types, complexity, duplication, tests, security
$S/hotspots.sh path/to/project 20                     # where to look first
$S/verify_package.sh pypi requests some-new-package   # does this dependency really exist?
```

---

## Manage

```bash
./install.sh --status                  # what is installed where, which version
./install.sh --all --uninstall         # remove everything the installer added
./install.sh --all --dry-run           # preview any command
```

The installer never overwrites or deletes a skill folder it didn't create. It edits
`AGENTS.md` only inside its own marked block and leaves your content alone.

---

## Customize for your organization

Edit the source in `skills/ship-ready/` (one place; installs follow):

| To change | Edit |
|---|---|
| Thresholds (coverage, mutation score, complexity) | `references/qa-techniques.md` §10 |
| House style, architecture layers, error taxonomy | `references/coding-standards.md` |
| Security requirements (e.g. ASVS level) | `references/security.md` |
| Approved tools per language | `references/coding-standards.md` §10, `scripts/quality_gate.sh` |
| CI platform | `templates/ci-github-actions.yml` |

The skill always defers to a repository's own configuration (`AGENTS.md`, linter
configs, ADRs), so per-repo exceptions need no fork.

Then run `tools/validate_skill.sh`, run the evals, bump `VERSION` and
`metadata.version`, and add a `CHANGELOG.md` entry.

---

## Quality of the skill itself

| Check | Command |
|---|---|
| Agent Skills spec compliance (name, description, size, links, scripts) | `tools/validate_skill.sh` |
| Installer integration tests (36 cases: scopes, guardrails, migration, safety, uninstall) | `tests/test_install.sh` |
| Behavioral evals with and without the skill | `evals/run.sh <scenario>` (see `evals/README.md`) |
| All of the above plus ShellCheck on Linux and macOS | `.github/workflows/ci.yml` |

## Repository layout

```
skills/ship-ready/   the skill (single source of truth)
  SKILL.md                        Quick + Full modes, gates, rationalizations (≈280 lines)
  guardrails.md                   5 always-on rules installed into agent instruction files
  references/                     standards, performance, QA, security, AI pitfalls, checklist, report format
  scripts/                        quality_gate.sh, hotspots.sh, verify_package.sh
  templates/                      README, ADR, PR template, CI, Makefile, pre-commit
install.sh                        multi-agent installer
evals/                            fixture, scenarios, trigger queries, runner, answer key
tools/validate_skill.sh           spec validator
tests/test_install.sh             installer tests
```

## Sources

Built from Anthropic's Agent Skills best practices and the agentskills.io specification;
Google Engineering Practices and *Software Engineering at Google*; OWASP Top 10:2025, OWASP
LLM Top 10 2025, ASVS 5.0, CWE Top 25 2025, SLSA, OpenSSF Scorecard; SonarSource
cognitive complexity; published research on AI-generated code (Veracode 2025, Perry et al.
2023, Spracklen et al. 2025, GitClear 2025, METR 2025, DORA 2024–25). Also informed by the
strongest public skills: obra/superpowers, addyosmani/agent-skills, trailofbits/skills,
Anthropic's code-review plugin, mattpocock/skills, getsentry/skills.
