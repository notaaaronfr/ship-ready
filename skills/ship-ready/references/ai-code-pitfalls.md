# Failure Modes of AI-Generated Code

## Contents
1. What the data says
2. Pitfall catalog
3. Quick grep sweep

---

## 1. What the data says

| Finding | Source |
|---|---|
| ~45% of AI-generated code samples contained a security flaw; models failed to prevent XSS in 86% and log injection in 88% of relevant cases; larger models were not more secure | Veracode GenAI Code Security Report, 2025 (vendor study) |
| Developers with an AI assistant wrote less secure code **and** were more confident it was secure | Perry et al., Stanford, ACM CCS 2023 |
| ~20% of packages recommended by code models did not exist (5% for commercial models, 22% for open models); fake names recur across runs | Spracklen et al., USENIX Security 2025 |
| Copy-pasted code rose and refactoring ("moved" lines) fell from ~16% to ~3% of changes, 2020–2024 | GitClear 2025 (correlational) |
| Experienced developers were 19% slower with AI tools while believing they were 20% faster | METR randomized trial, 2025 |
| Higher AI adoption associated with lower delivery stability; "AI amplifies what already exists" | DORA 2024 / 2025 |

Implication: review AI code harder than human code, verify instead of trusting
confidence, and watch for duplication and missing authorization in particular.

## 2. Pitfall catalog

| # | Pitfall | What it looks like | Fix |
|---|---|---|---|
| 1 | **Hallucinated APIs** | Functions, parameters or config keys that don't exist in the pinned version | Run it; type-check; read the pinned version's docs |
| 2 | **Hallucinated packages** | Plausible but non-existent or brand-new dependency | `scripts/verify_package.sh`; reject < 90 days old or tiny download counts without review |
| 3 | **Happy path only** | No handling for empty, null, timeout, partial failure | Boundary and failure tests; explicit error handling |
| 4 | **Silent failures** | `except: pass`, `catch (e) { console.log(e) }`, return `[]`/default/mock on error | Narrow the catch; re-raise with context; fail closed |
| 5 | **Authentication without authorization** | Checks the user is logged in, not that they own the object | Ownership check on every object access (CWE-862/639) |
| 6 | **Accidental O(n²)** | `in list` inside loops, nested matching loops, sorting in loops | `performance-complexity.md` §4 |
| 7 | **God functions** | 200 lines doing parse + validate + DB + format | Extract by responsibility; functional core / imperative shell |
| 8 | **Duplicated helpers** | Same utility re-implemented in several files | Search the repo before writing; consolidate; add duplication detection to CI |
| 9 | **Over-engineering** | Factories, abstract base classes, strategy patterns with one implementation | Deletion test; inline |
| 10 | **Fake or tautological tests** | Asserts a mock was called; expected value computed by the code under test; `assert x is not None` | Assert real outputs; mutation-test |
| 11 | **Tests edited to pass** | Assertions loosened, tests skipped or deleted in the same change as the fix | Review test diffs separately; reject weakened assertions |
| 12 | **Hard-coded secrets and config** | API keys, URLs, paths in source | Environment / secret manager; rotate anything leaked |
| 13 | **Insecure defaults** | `verify=False`, `shell=True`, `eval`, string-built SQL, CORS `*`, `yaml.load`, `pickle` on input | Safe equivalents; SAST |
| 14 | **Unbounded resources** | No pagination, no size limits, no timeouts, unbounded caches | Bounds and timeouts everywhere |
| 15 | **Outdated idioms** | Deprecated APIs, old syntax, unmaintained libraries | Current idioms; dependency audit |
| 16 | **Misleading comments** | Docstrings describing intended, not actual, behavior | Make them match the code, or delete |
| 17 | **Leftover scaffolding** | `TODO: implement`, placeholder returns, debug prints, unused imports | Lint; grep sweep |
| 18 | **Float money, naive datetimes** | `price * 0.1`, `datetime.now()` | Decimal or integer cents; timezone-aware UTC |
| 19 | **Non-determinism** | Unseeded randomness, wall-clock in logic, ordering assumptions on sets/maps | Inject clock and RNG; explicit ordering |
| 20 | **Inconsistent conventions** | Each generated file follows a different style or error strategy | Align to the repo's conventions; formatter + linter |
| 21 | **Silent behavior change in "refactor"** | Rewrite subtly changes outputs, ordering or error types | Characterization tests before any rewrite |
| 22 | **Prompt-injectable LLM integration** | Model output passed to shell, SQL, HTML or tool selection | `security.md` §4 |

## 3. Quick grep sweep

Starting points for Phase 2, not a substitute for reading the code. Uses POSIX `grep -E`.

```bash
# Swallowed or overly broad error handling
grep -rnE "except:|except Exception( as [a-z_]+)?:[[:space:]]*(pass)?$|catch[[:space:]]*\([^)]*\)[[:space:]]*\{[[:space:]]*\}|\.catch\(\(\)[[:space:]]*=>" --include=*.py --include=*.ts --include=*.js --include=*.java .

# Scaffolding and debug leftovers
grep -rnE "TODO|FIXME|XXX|HACK|NotImplementedError|console\.log\(|print\(" --include=*.py --include=*.ts --include=*.js .

# Insecure calls
grep -rnE "verify[[:space:]]*=[[:space:]]*False|shell[[:space:]]*=[[:space:]]*True|\beval\(|\bexec\(|yaml\.load\(|pickle\.loads?\(|dangerouslySetInnerHTML|innerHTML[[:space:]]*=" .

# String-built SQL
grep -rnE "(execute|query|raw)\([[:space:]]*(f[\"']|[\"'].*(%s|\+|\{))" --include=*.py --include=*.ts --include=*.js .

# Possible hard-coded secrets (use gitleaks for real scanning)
grep -rnEi "(api[_-]?key|secret|password|passwd|token)[[:space:]]*[:=][[:space:]]*[\"'][^\"']{8,}[\"']" .

# Float money
grep -rnEi "(price|amount|total|balance|cost)[a-z_]*[[:space:]]*[*/][[:space:]]*[0-9]+\.[0-9]+" --include=*.py --include=*.ts --include=*.js .
```
