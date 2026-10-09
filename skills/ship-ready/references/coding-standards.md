# Coding Standards

## Contents
1. Readability
2. Simplicity: reduce, don't relocate
3. Structure and design
4. Smell → refactoring map
5. Error handling (fail closed)
6. Types and contracts
7. Resilience at boundaries
8. Logging, observability, configuration
9. Concurrency
10. Tooling per language
11. Commits and review

The repository's existing conventions override everything here. Consistency with the
codebase beats a "better" style applied to one file.

---

## 1. Readability

| Do | Don't |
|---|---|
| `calculate_invoice_total(line_items)` | `calc(d)`, `process_data()`, `handle()` |
| Booleans read as questions: `is_active`, `has_access`, `can_retry` | `flag`, `status2`, `check` |
| `MAX_RETRY_ATTEMPTS = 3` | Bare `3` inside logic |
| Guard clauses and early returns | Five levels of nested `if` |
| One idea per line | One-liners that need a comment to decode |
| Comments explain **why** | Comments that restate **what** |

**Limits (defaults; repo config wins):**
- Cognitive complexity ≤ 15 per function (SonarSource; penalizes nesting).
- Cyclomatic complexity ≤ 10.
- Nesting ≤ 3 levels.
- Function ≤ ~40 lines; ≤ 4 parameters (group the rest into a parameter object).
- File ≤ ~400 lines; class ≤ ~20 methods.

Crossing a limit is a smell to explain, not an automatic violation.

## 2. Simplicity: reduce, don't relocate

- **Concept count:** after a refactor, count the names, types and branches a reader
  must hold to understand the change. It must go down. Moving code into a new file,
  class or helper without reducing concepts is relocation, so revert it.
- **Deletion test:** for each abstraction (interface, factory, base class, wrapper),
  ask: would deleting it and inlining its one use make the code simpler? If yes, delete it.
- **Rule of Three:** duplicate twice, abstract on the third. The wrong abstraction costs
  more than duplication.
- **YAGNI:** no extension points for requirements nobody has stated.
- **Chesterton's fence:** before removing strange code, learn why it exists
  (`git log -L :fn:file`, blame, linked issues, ADRs).

## 3. Structure and design

- **Single responsibility:** one reason to change per function or class.
- **Functional core, imperative shell:** pure business logic in the middle; I/O
  (DB, HTTP, files, clock, randomness) at the edges and injected. This is the biggest
  lever for testability.
- **Dependency injection:** pass collaborators in; don't reach for globals deep inside logic.
- **Layering:** entry points (`api/`, `cli/`) → use cases (`services/`) → `domain/` ←
  `adapters/` (DB, HTTP clients). Dependencies point inward; the domain imports no framework.
- **Composition over inheritance;** inheritance deeper than 2 is a smell.
- **Hotspot priority:** improve code where churn × complexity is high (`scripts/hotspots.sh`).
  Low-health files that change often are where defects cluster (CodeScene's "Code Red"
  study: up to 15× more defects in unhealthy code).

```
src/<package>/
├── domain/      entities, value objects, pure rules (no I/O)
├── services/    use cases orchestrating domain + ports
├── adapters/    DB, HTTP clients, queues
├── api/         HTTP/CLI handlers, request/response DTOs
└── config.py    typed settings loaded from environment
tests/{unit,integration,e2e}/   docs/adr/   Makefile   README.md
```

## 4. Smell → refactoring map

Smells are labeled heuristics ("possible feature envy"), not verdicts.

| Smell | Signal | Refactoring |
|---|---|---|
| Long function | > 40 lines, several comment-separated sections | Extract function per section |
| Deep nesting / bumpy road | Nested `if`/loops, several complex blocks in one function | Guard clauses; extract; decompose conditional |
| Long parameter list | > 4 params, same group passed together | Introduce parameter object |
| Primitive obsession | Money as float, IDs as raw strings, status as strings | Value objects, enums |
| Feature envy | Method uses another object's data more than its own | Move method |
| Data clumps | Same 3 fields travel together | Extract class |
| Shotgun surgery | One change touches many files | Move function/field to consolidate |
| Divergent change | One class changed for unrelated reasons | Split class |
| Duplicated code | Same block in ≥ 3 places | Extract and reuse (search the repo first) |
| Speculative generality | Interface or factory with one implementation | Inline; delete |
| Flag argument | `do_thing(x, True)` | Split into two named functions |
| Temporal coupling | Must call `init()` before `run()` | Constructor establishes invariants |
| Mutable shared state | Globals, module-level dicts mutated | Pass state explicitly; immutable data |

## 5. Error handling (fail closed)

- Validate input at the boundary with a schema (Pydantic, Zod, Bean Validation).
- Never swallow: no bare `except:`, `except Exception: pass`, empty `catch {}`, or
  `.catch(() => {})`. Catch the narrowest type you can handle.
- For every catch, list the failures it can hide. If you can't, it's too broad.
- No **silent fallbacks**: returning a default, an empty list or a mock on error must be
  an explicit, documented, logged product decision, never a convenience.
- Errors on security decisions **deny** (fail closed), never allow.
- Domain-specific errors (`InsufficientFundsError`), re-raised with context
  (`raise X from e`, `fmt.Errorf("load user %d: %w", id, err)`).
- Per error, decide: **retry** (transient), **surface** (caller's fault), or **crash** (bug).
- Release resources deterministically: `with`, `try/finally`, `using`, `defer`.

## 6. Types and contracts

- Type every public signature; strict mode (`mypy --strict`, `tsc --strict`).
- Prefer immutable data (`@dataclass(frozen=True)`, `readonly`, records).
- Make illegal states unrepresentable: enums and tagged unions over stringly-typed flags.
- Avoid `Any`; isolate unavoidable dynamic data behind a typed adapter.
- Money: integer minor units or `Decimal`, never float. Time: timezone-aware UTC.

## 7. Resilience at boundaries

- **Timeout** on every network, DB and model call.
- **Retries:** only for transient errors and idempotent operations; capped exponential
  backoff with jitter; a maximum attempt count.
- **Idempotency keys** for mutating operations that may be retried.
- **Circuit breaker / bulkhead** around flaky dependencies; graceful degradation.
- **Bounded everything:** page sizes, upload sizes, queue lengths, recursion depth.
- Separate liveness from readiness health checks.

## 8. Logging, observability, configuration

- Structured (JSON) logs with level, message, correlation/request ID. No `print`.
- Log at boundaries and errors; never secrets, tokens or PII.
- Metrics for rate, errors, duration (RED); traces across services (OpenTelemetry).
- Configuration from environment or a secret manager, validated at startup into a typed
  object; fail fast on missing config.
- Risky changes behind feature flags with a rollback path.

## 9. Concurrency

- Prefer immutable data and message passing to shared mutable state.
- Every lock: documented acquisition order, minimal scope.
- Every concurrent fan-out: a concurrency limit and cancellation.
- Test for races where the language supports it (`go test -race`, ThreadSanitizer).

## 10. Tooling per language

| Language | Format | Lint | Types | Test | Coverage | Mutation | Security |
|---|---|---|---|---|---|---|---|
| Python | ruff format | ruff | mypy / pyright | pytest | pytest-cov | mutmut | bandit, pip-audit |
| TS/JS | prettier | eslint + typescript-eslint + sonarjs | tsc --strict | vitest / jest | built-in / c8 | Stryker | npm audit, semgrep |
| Java/Kotlin | spotless | PMD, checkstyle, detekt | compiler | JUnit 5 | JaCoCo | PIT | SpotBugs + FindSecBugs, OWASP dep-check |
| Go | gofmt | golangci-lint | compiler | go test | -cover | gremlins | gosec, govulncheck |
| C# | dotnet format | Roslyn analyzers | compiler | xUnit | coverlet | Stryker.NET | security-code-scan |
| Rust | rustfmt | clippy -D warnings | compiler | cargo test | cargo-llvm-cov | cargo-mutants | cargo audit |

## 11. Commits and review

- Small changes: ~100 changed lines is easy to review; ~1,000 should be split.
- One logical change per commit; refactors and behavior changes in **separate** commits.
- Conventional Commits (`feat:`, `fix:`, `refactor:`, `perf:`, `test:`, `docs:`).
- Approve a change when it clearly improves overall code health, even if it isn't perfect.
  Prefix optional suggestions with "Nit:".
- PR description: why, how it was tested, performance impact, risk and rollback.
