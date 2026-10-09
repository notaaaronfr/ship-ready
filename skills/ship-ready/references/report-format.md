# Report Format

## Contents
Markdown report · JSON report · Allowed values and verdict rule

Produce two artifacts: `QUALITY_REPORT.md` for people (or the final chat message if
the user did not want files) and `.quality/report.json` for CI and dashboards.

## Markdown report

```markdown
# Quality report: <component>    (<date>, skill v2.0.0, depth S|M|L)

## Verdict
<READY | READY WITH CONDITIONS | NOT READY>: one sentence why.

## Baseline → after
| Metric | Before | After |
|---|---|---|
| Lint / type errors | 41 / 17 | 0 / 0 |
| Tests (pass / total) | 12 / 14 | 96 / 96 |
| Line / branch coverage | 38% / 21% | 87% / 74% |
| Mutation score (changed modules) | n/a | 71% |
| Max cognitive complexity | 48 (`process_order`) | 12 |
| Duplicated blocks | 9 | 1 |
| High/critical security findings | 3 | 0 |

## Findings ledger
| ID | Sev | Conf | Location | Finding | Status | Evidence |
|---|---|---|---|---|---|---|
| F-001 | P0 | HIGH | api/orders.py:42 | SQL built by string formatting (CWE-89) | Fixed | test_order_lookup_rejects_injection red→green |
| F-007 | P1 | HIGH | orders/service.py:88 | Swallowed exception charges full price | Fixed | test_malformed_coupon |
| F-012 | P1 | MED | billing/tax.py:30 | Float used for money | Needs verification | rounding diff seen at 1e6 items |
| F-015 | P2 | HIGH | utils.py | Duplicate date parsing ×3 | Capped, NOT converged | see notes |

## Performance
| Function | Before | After | Benchmark (n=10⁵, median ± IQR) |
|---|---|---|---|
| `match_customers` | O(n·m) time | O(n+m) time, O(m) space | 1.84 s ± 0.03 → 41 ms ± 2 |
Reverted attempts: `cache_tax_rates` (neutral, within noise).

## Maturity scorecard (0 Missing, 1 Weak, 2 Moderate, 3 Satisfactory, 4 Strong)
| Category | Score | Evidence |
|---|---|---|
| Correctness & error handling | 3 | … |
| Security | 3 | … |
| Testing | 3 | … |
| Readability & structure | 3 | … |
| Performance | 4 | … |
| Operability (logs, config, metrics) | 2 | … |
| Documentation & handoff | 3 | … |
| **Overall** | **2** | Lowest category sets the ceiling: any 1 makes the overall at most 1 |

## Coverage attestation
- Fully read: <files>
- Partially read / sampled: <files and why>
- Not verified: <claims, and what would verify them>
- Evidence level reached: source | build | runtime
- Gates that could not run: <tool, reason>

## Behavior changes
<every intentional change in observable behavior, with the commit>

## Out of scope / follow-ups
<pre-existing issues seen but not addressed, with suggested priority>

## How to verify
`make check` (or the exact commands)
```

## JSON report

```json
{
  "schema": "ship-ready/report@1",
  "skill_version": "2.0.0",
  "component": "orders-service",
  "date": "2026-10-09",
  "depth": "M",
  "verdict": "READY_WITH_CONDITIONS",
  "metrics": {
    "before": {"lint_errors": 41, "type_errors": 17, "tests_passed": 12, "tests_total": 14,
               "line_coverage": 0.38, "branch_coverage": 0.21, "mutation_score": null},
    "after":  {"lint_errors": 0, "type_errors": 0, "tests_passed": 96, "tests_total": 96,
               "line_coverage": 0.87, "branch_coverage": 0.74, "mutation_score": 0.71}
  },
  "findings": [
    {"id": "F-001", "severity": "P0", "confidence": "HIGH", "file": "api/orders.py", "line": 42,
     "category": "security", "cwe": "CWE-89", "title": "SQL built by string formatting",
     "status": "fixed", "evidence": "test_order_lookup_rejects_injection red->green"}
  ],
  "scorecard": {"correctness": 3, "security": 3, "testing": 3, "readability": 3,
                "performance": 4, "operability": 2, "documentation": 3, "overall": 2},
  "attestation": {"evidence_level": "runtime", "not_verified": [], "gates_skipped": ["semgrep: not installed"]},
  "not_converged": ["F-015"]
}
```

Allowed values: `severity` P0–P3; `confidence` HIGH | MEDIUM; `status` fixed |
open | needs_verification | capped_not_converged | out_of_scope | wont_fix;
`verdict` READY | READY_WITH_CONDITIONS | NOT_READY.

Every metric must come from a command run after the last edit; otherwise use `null` in
JSON and "not measured" in Markdown. Mutation results from hand-made mutants go in
`"mutation_spot_check": "3/3"`, never in `mutation_score`.

**Verdict rule** (computed by `scripts/verdict.py`; never hand-written): any open P0 → NOT_READY. Any open P1, or a gate skipped for a missing
tool → READY_WITH_CONDITIONS (list them). Otherwise READY.
