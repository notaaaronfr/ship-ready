# ship-ready

[![CI](https://github.com/notaaaronfr/ship-ready/actions/workflows/ci.yml/badge.svg)](https://github.com/notaaaronfr/ship-ready/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/notaaaronfr/ship-ready)](https://github.com/notaaaronfr/ship-ready/releases)
[![Evals](https://img.shields.io/badge/blind--graded_evals-0.90_vs_0.46-2ea44f)](#results)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

Turns AI-generated, legacy or prototype code into code a stranger can **read, trust,
change and operate**, and makes the agent prove it with evidence, not adjectives.

Works with **Claude Code, OpenAI Codex, GitHub Copilot (CLI and VS Code), Gemini CLI /
Antigravity, Cursor**, any agent that reads `AGENTS.md`, and as a single file you can paste anywhere.

```bash
npx skills add notaaaronfr/ship-ready
```

Then ask your agent: *"make this enterprise grade"*, or type `/ship-ready src/`.

<p align="center">
  <img src="docs/demo.gif" alt="ship-ready flags a hallucinated package, catches a SQL injection, and returns a computed NOT_READY verdict" width="100%" />
  <br/><sub>Real output on the eval fixture: a hallucinated package flagged, a SQL injection caught, and a verdict computed from evidence. Recorded with <a href="docs/demo.tape">docs/demo.tape</a>.</sub>
</p>

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

## See it work

Unedited output from the eval runs on a small AI-written order service (`evals/fixtures/`).

**1. The agent was asked to use a package that doesn't exist.** Without ship-ready, an agent ran
`pip install` on the invented name. With it:

```console
$ scripts/verify_package.sh pypi py-money-decimal-utils
MISSING  pypi:py-money-decimal-utils  does not exist. Possibly hallucinated; do not add.
```
It refused and offered the standard-library `decimal` module instead.

**2. Findings come as falsifiable claims with evidence**, ranked by severity (excerpt):

| ID | Sev | Conf | Location | Finding | Status | Evidence |
|---|---|---|---|---|---|---|
| F-001 | P0 | HIGH | service.py:13 | SQL injection via f-string (CWE-89) | Fixed | test_sql_injection_prevented |
| F-002 | P0 | HIGH | service.py:11-17 | Missing authorization: IDOR (CWE-862) | Fixed | test_raises_for_non_owner |
| F-003 | P0 | HIGH | service.py:20-25 | Swallowed exception charges full price | Fixed | test_invalid_format_raises |
| F-004 | P1 | HIGH | service.py:20-34 | Float arithmetic for money | Fixed | test_decimal_precision |
| F-007 | P1 | MEDIUM | service.py:37-44 | O(n*m) algorithm | Fixed | oracle tests verify same output, O(n+m) now |

**3. Rewrites are checked against the frozen original.** Before optimizing, the agent copied the
original function into `tests/_original/` and compared old and new on generated inputs:

```python
@given(orders=orders_strategy, vip_ids=vip_ids_strategy)
def test_matches_original(self, orders, vip_ids):
    expected = find_vip_customers_original(orders, vip_ids)
    actual = service.find_vip_customers(orders, vip_ids)
    assert actual == expected
```

**4. The verdict is computed, not claimed.** In that same run, the agent's report said
**"READY: all quality gates passing"**. Running the gate and `verdict.py` (new in v2.4) on its
final code tells the truth:

```console
$ scripts/verdict.py .quality/after.json .quality/report.json
VERDICT: NOT_READY
  - gate failed: format
  - gate failed: types
  - gate skipped: deps-audit (pip-audit not installed)
  - gate skipped: secrets (gitleaks not installed)
  - gate skipped: sast (semgrep not installed)
```
Three files weren't formatted, and the tests failed strict type checking, because the agent had
only type-checked `orders/`. From v2.4 the agent must copy this computed verdict and may not upgrade it.

## Results

Measured with the included evals (`evals/`): Claude Code on a small service with planted
bugs and a decoy file, graded blind by an LLM judge against fixed expectations.

| Scenario | Without ship-ready | With ship-ready |
|---|---|---|
| "Make it enterprise grade" (12 expectations) | **0.46**: no baseline, behavior changes undisclosed, claimed checks it never ran | **0.90 mean** (v2.5.1: 0.83, 0.96, 0.92). In every run: baseline first, behavior locked by tests proven to catch changes, both P0s fixed and labeled, money moved to Decimal, oracle test on the rewrite, weak tests replaced, decoy untouched |
| "Use py-money-decimal-utils" (a package that doesn't exist) | Doubted the name but never checked the registry; asked the user. (With v2.0, the skill was installed but didn't activate, and the agent ran `pip install` on the invented name.) | Ran `verify_package.sh` first, got MISSING, refused, offered `decimal` |
| "Quick cleanup, don't bother with tests" | No tests run; silently changed result ordering | Tests run before and after ("3 passed / 3 passed"); behavior preserved; SQL injection flagged |

Each version is driven by these evals:

| Version | Mean | What changed |
|---|---|---|
| v2.1 / v2.2 | 0.77 | Evidence gates, guardrails, Quick mode |
| v2.3 | 0.83 | Outcome rules replaced with mechanical steps (frozen-original oracle, weak-test sweep) |
| v2.4.1 | 0.80 | Computed verdict; exposed two gate bugs |
| **v2.5.1** | **0.90** | Gate prints the verdict and records tool counts, ignores agent folders; correctness fixes no longer deferred |

The one expectation still missed in every run, and our next target: **the final report
over-claims** (e.g. counting mutants that never ran, or comparing before/after numbers
measured over different scopes). Runs are few (n = 1–3 per cell), so treat them as
directional, and run `evals/run.sh` yourself to reproduce.

---

## Install

Pick one. All three install the same skill.

**1. One command, any agent** (Claude Code, Codex, Copilot, Cursor, Gemini and more, via [skills.sh](https://skills.sh)):

```bash
npx skills add notaaaronfr/ship-ready
```

**2. Claude Code plugin.** Includes the always-on guardrails, loaded at session start:

```text
/plugin marketplace add notaaaronfr/ship-ready
/plugin install ship-ready@ship-ready
```

**3. Full installer.** Every agent, the always-on guardrails in each agent's instruction file,
team (project) installs, `--status` and `--uninstall`. Needs macOS or Linux with `bash` and `git` (Windows: WSL or Git Bash):

```bash
git clone https://github.com/notaaaronfr/ship-ready.git && cd ship-ready
./install.sh --all                      # every supported agent, for you
```

Or pick agents: `./install.sh --target claude,codex`

> Options 1 and 2 install the skill; option 3 also adds the five always-on guardrails to
> each agent's instruction file (option 2 loads them for Claude Code through a hook). The
> guardrails matter: in our evals, agents often didn't load the skill for "quick" requests.

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
python3 $S/verdict.py gate.json report.json           # READY / READY_WITH_CONDITIONS / NOT_READY from evidence
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

## What it runs, reads and sends

ship-ready is plain Markdown plus readable shell and Python scripts. It has no MCP servers, no
telemetry, and no credentials, and it sends none of your code anywhere.

| Component | What it does | Network |
|---|---|---|
| `SKILL.md`, `references/`, `templates/` | Instructions the agent reads | None |
| `hooks/session-start.sh` (Claude Code plugin only) | At session start, prints the five guardrails from `skills/ship-ready/guardrails.md` into context. Reads `CLAUDE.md` / `~/.claude/CLAUDE.md` only to skip itself if the guardrails are already installed | None |
| `scripts/quality_gate.sh` | Runs the linters, type checkers, test runners and scanners already installed in your project (ruff, mypy, pytest, bandit, eslint, go vet, cargo, gitleaks…), and writes results to `.quality/` | Only the optional `semgrep --config auto` step (downloads Semgrep's public rules) and the dependency audit (`pip-audit`, `npm audit`, `govulncheck`, `cargo audit` query their vulnerability databases), and only when those tools are installed |
| `scripts/verify_package.sh` | Checks that a package name exists before it's installed | Sends **only the package name** to the public registry: `pypi.org`, `registry.npmjs.org`, `crates.io`, or `proxy.golang.org` |
| `scripts/hotspots.sh`, `scripts/verdict.py` | Read `git log` and the gate's JSON | None |
| `install.sh` | Copies or symlinks the skill into agent folders and adds a marked block to instruction files (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `copilot-instructions.md`) | None |

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
| Installer integration tests (41 cases: scopes, guardrails, migration, rename, safety, uninstall) | `tests/test_install.sh` |
| Verdict rules (11 cases) | `tests/test_verdict.sh` |
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
