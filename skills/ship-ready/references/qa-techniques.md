# QA Techniques

## Contents
1. Test sizes and the portfolio
2. Static QA
3. Test design: choosing inputs
4. Characterization tests (legacy and AI code)
5. Property-based testing
6. Mutation testing
7. Integration, contract and end-to-end
8. Test smells to reject
9. Flaky tests
10. Quality gates

---

## 1. Test sizes and the portfolio

Classify tests by **what they are allowed to touch**, not by name (Google's test sizes):

| Size | Constraints | Typical share |
|---|---|---|
| Small | One process, no network, disk, sleep or clock; < 1 s each | Most tests (~70%) |
| Medium | One machine; localhost services (DB in a container) | ~20% |
| Large | Multiple machines / real external systems | Few, for critical journeys (~10%) |

Pyramid vs trophy is a false fight: maximize **fast and deterministic** checks; add
integration tests where the risk is in the wiring (DB, serialization, HTTP), which in
CRUD-heavy services is most of the risk.

Prefer **real implementations > fakes > stubs > mocks**. Assert on **state and
outputs**, not on which methods were called. Mocks belong only at architectural
boundaries you don't own.

## 2. Static QA

| Technique | Catches | Tools |
|---|---|---|
| Formatter | Diff noise | ruff format, prettier, gofmt, rustfmt |
| Linter | Bug patterns, unused code | ruff, eslint, golangci-lint, clippy |
| Type checker (strict) | Type and null errors | mypy/pyright, tsc --strict |
| Cognitive complexity | Hard-to-read functions | SonarQube/SonarLint, eslint-plugin-sonarjs, radon, lizard |
| Duplication | Copy-paste growth (rising sharply with AI assistants) | jscpd, PMD CPD |
| SAST | Injection, unsafe APIs | semgrep, CodeQL, bandit, gosec |
| Secrets | Leaked keys | gitleaks, trufflehog |
| Dependency audit | Known CVEs, licenses | pip-audit, npm audit, osv-scanner, govulncheck |

## 3. Test design: choosing inputs

| Technique | How | Example: `age` valid 18–65 |
|---|---|---|
| Equivalence partitioning | One value per class | 10, 30, 80 |
| Boundary values | On and around each edge | 17, 18, 19, 64, 65, 66 |
| Decision tables | Every condition combination → action | Discount rules |
| State transitions | Valid and invalid transitions | shipped → paid must fail |
| Pairwise | All value pairs, not all combinations | Config matrices |
| Error guessing | Known breakers | `None`, `""`, `[]`, unicode, emoji, huge n, negative, NaN, duplicates, DST, leap day, timezones |
| **Skeletons** | Every existing `try/except`, null check, retry and special case marks a past failure: test it | 2–3 boundary tests per core file |

## 4. Characterization tests

For code without trustworthy tests (typical of AI-generated and legacy code):

1. Choose seams: public functions, CLI, HTTP endpoints.
2. Feed realistic and edge inputs; **record** current outputs (golden files / approval
   tests / snapshot). Include current weird behavior, marked `# BUG? F-xxx`.
3. **Sensitivity proof:** inject a deliberate change, watch the suite fail, revert.
4. Keep snapshots small and human-reviewed; never bulk-approve.
5. After refactoring, the same suite must pass unchanged.

```python
@pytest.mark.parametrize("case", load_cases("tests/golden/orders/*.json"), ids=str)
def test_order_totals_unchanged(case):
    assert compute_totals(case.input) == case.expected   # recorded before refactor
```

## 5. Property-based testing

Generate hundreds of inputs and check rules that must always hold. Climb this ladder;
higher rungs catch more:

1. **No crash**: function never raises for valid input.
2. **Type / shape preservation**: output has expected type, length, keys.
3. **Invariant**: e.g. sorted output is a permutation of the input.
4. **Idempotence**: `f(f(x)) == f(x)` (normalizers, dedupe, formatting).
5. **Round-trip**: `decode(encode(x)) == x` (serializers, parsers).
6. **Oracle**: `new(x) == reference(x)`. **The key property for refactors and
   optimizations**: the old implementation is the reference.

Also: commutativity, metamorphic relations (`search(q)` ⊇ `search(q + " filter")` results).

Reject two failure modes:
- **Tautology**: the expected value is computed with the code under test.
- **Vacuity**: `assume()`/filters discard most inputs; check the generator's statistics.

```python
from hypothesis import given, strategies as st

@given(st.lists(st.integers()), st.lists(st.integers()))
def test_optimized_matches_original(orders, vips):
    assert match_fast(orders, vips) == match_original(orders, vips)   # oracle
```

Tools: Hypothesis, fast-check, jqwik, proptest, FsCheck, gopter / `testing/quick`.

## 6. Mutation testing

Mutation testing injects small bugs (flip `<` to `<=`, drop a call, return a constant)
and reruns the tests. A **surviving mutant** means nothing checks that behavior. It
measures test *strength*; coverage only measures test *reach*.

Tools: mutmut / cosmic-ray (Python), Stryker (JS/TS, C#, Scala), PIT (Java/Kotlin),
cargo-mutants (Rust), go-mutesting / gremlins (Go).

Practice:
- Run on **changed critical modules** (incremental mode: Stryker `--incremental`, PIT history), not the whole repo.
- Triage every survivor:
  - **Missing assertion** → add a test that kills it.
  - **Equivalent mutant** (cannot change observable behavior) → document and ignore.
  - **Timeout** → inconclusive, not a kill. Investigate infinite loops.
- Prioritize by what the code does (money, auth, persistence), not by mutation operator.
- No tool? Manual spot-check: invert three conditions in the changed code; each must turn a test red.

## 7. Integration, contract and end-to-end

- **Integration:** real dependencies in containers (Testcontainers, docker compose). Cover
  transactions, migrations, serialization, timeouts, retries, idempotency.
- **Contract:** consumer-driven contracts (Pact) or OpenAPI schema checks between services,
  verified on the provider before deploy, instead of brittle cross-service E2E.
- **End-to-end:** critical user journeys only (Playwright/Cypress). Seeded data, no sleeps,
  explicit waits.
- **Load:** k6, Locust, Gatling against an SLO (p95/p99 latency, error rate, throughput).
- **Fuzzing:** parsers and anything reading untrusted bytes (atheris, go fuzz, cargo-fuzz, AFL++).

## 8. Test smells to reject

| Smell | Fix |
|---|---|
| Assertion roulette (many unlabeled asserts) | One behavior per test; descriptive messages |
| Interaction-only assertions (`mock.assert_called`) | Assert on outputs or state |
| Tautological expected values | Hard-code or derive independently |
| Sleepy test (`sleep(2)`) | Inject the clock; explicit waits |
| Mystery guest (hidden fixture files) | Build data inside the test or name the fixture clearly |
| Eager test (tests five behaviors) | Split |
| Conditional logic in tests | Parametrize instead |
| `assert result is not None` as the only check | Assert the actual value |

Prefer DAMP (descriptive and meaningful) over DRY in tests: readable repetition beats clever helpers.

## 9. Flaky tests

At Google, ~16% of tests showed some flakiness. A flaky test is a bug: quarantine within
a day with an owner and a deadline; fix or delete. Usual causes: time, randomness without
seed, ordering, shared state, real network, sleeps, test-order dependence.

## 10. Quality gates

| Gate | Threshold |
|---|---|
| Formatter, linter | 0 errors |
| Type check (strict) | 0 errors in changed code |
| Tests | 100% pass; no skips without a ticket |
| Line coverage (changed code) | ≥ 80% |
| Branch coverage (core logic) | ≥ 70% |
| Mutation score (changed critical modules) | ≥ 60% (aim for 75%+ on money/auth) |
| Cognitive complexity per function | ≤ 15 |
| Duplicated blocks introduced | 0 |
| SAST / secrets | 0 high or critical |
| Dependency audit | 0 known critical CVEs |
| Benchmarks on optimized paths | No regression beyond noise |

Thresholds are defaults. The repository's configured thresholds win.
