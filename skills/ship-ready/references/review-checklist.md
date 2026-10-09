# Review Checklist

## Contents
Spec · Correctness · Error handling · Security · Design & readability · Performance ·
Tests · Operability · Documentation · Before reporting

For each item, mark it clean or record a finding (`F-nnn [P0–P3][HIGH|MEDIUM] file:line`).
Items you did not check go into the report's coverage attestation as "not verified".

## Spec
- [ ] Does the code do what was asked? Any requirement missing?
- [ ] Anything implemented that wasn't asked for (scope creep)?
- [ ] Anything "implemented but wrong": right shape, wrong behavior?

## Correctness
- [ ] Edge cases: empty, null, one element, max size, negative, zero, duplicates, unicode, DST/timezones, leap day, float precision.
- [ ] Off-by-one in loops, slices, ranges, pagination.
- [ ] Overflow, division by zero, integer/float mixing.
- [ ] Money as Decimal or integer minor units; times timezone-aware.
- [ ] State machines: every state has defined transitions; impossible states unrepresentable.
- [ ] Concurrency: races, shared mutable state, lock ordering, missing cancellation.
- [ ] Idempotency of anything that can be retried.
- [ ] Resources always released.
- [ ] Domain risks: correct-looking but wrong output? 10× scale? Killed mid-write?

## Error handling
- [ ] No swallowed errors; every catch names what it handles.
- [ ] No silent fallback to defaults, empty results or mocks.
- [ ] Security-relevant errors fail closed.
- [ ] Errors carry context; domain errors are typed.
- [ ] Timeouts on all external calls; retries bounded, with backoff and jitter, only when idempotent.
- [ ] Failures leave consistent state (transactions or compensation).

## Security (details in `security.md`)
- [ ] Input validated at the boundary.
- [ ] Authorization (not just authentication) on every object access.
- [ ] Parameterized queries; no shell/eval/unsafe deserialization on untrusted data.
- [ ] Output encoded for its context.
- [ ] No secrets, tokens or PII in code, logs, errors or URLs.
- [ ] New dependencies verified to exist and be legitimate; lockfile updated.
- [ ] LLM output treated as untrusted input.
- [ ] Every input-driven allocation is bounded.

## Design & readability
- [ ] Names reveal intent.
- [ ] Cognitive complexity ≤ 15, nesting ≤ 3, ≤ 4 parameters.
- [ ] Business logic separated from I/O and framework.
- [ ] No duplication of existing helpers (searched the repo); no dead code.
- [ ] No magic numbers or strings.
- [ ] No abstraction that fails the deletion test.
- [ ] Consistent with the repo's conventions.

## Performance
- [ ] Time, space and I/O round-trips of hot paths stated and acceptable.
- [ ] No N+1 queries; queries indexed; only needed columns.
- [ ] Large data streamed or paginated.
- [ ] Caches bounded with invalidation.

## Tests
- [ ] New or changed behavior has tests; bug fixes have a red→green regression test.
- [ ] Happy path, boundaries and failure paths covered.
- [ ] Assertions on outputs/state, not only on mock calls; no tautologies.
- [ ] Deterministic: no real clock, network or unseeded randomness.
- [ ] No tests weakened, skipped or deleted to make the change pass.

## Operability
- [ ] Structured logs with correlation IDs at boundaries and errors.
- [ ] Metrics/traces for new endpoints and jobs.
- [ ] Config validated at startup.
- [ ] Backward compatible (API, schema, messages) or migration documented.
- [ ] Feature flag or rollback plan for risky changes.

## Documentation
- [ ] README covers run, test, configure, deploy.
- [ ] ADR for every non-obvious decision.
- [ ] Docstrings explain why; algorithms state complexity.

## Before reporting
- [ ] Each P0/P1 restated as a falsifiable claim and traced end to end.
- [ ] Framework mitigations checked (ORM escaping, template auto-escape, middleware).
- [ ] LOW-confidence findings removed; MEDIUM marked "needs verification".
- [ ] Linter-catchable, out-of-scope and justified-suppression items removed from findings.
- [ ] If one structural problem dominates, it leads the report. Ten nits don't bury it.
