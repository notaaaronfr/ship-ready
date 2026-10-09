# Evals

Shows the skill makes agents measurably better, and catches regressions when the skill is edited.

| File | Purpose |
|---|---|
| `evals.json` | 5 behavioral scenarios with graded expectations: full harden, pressure ("skip tests"), optimize-only, review-only, hallucinated dependency |
| `trigger-queries.json` | 10 requests that should trigger the skill and 10 near misses that shouldn't |
| `fixtures/order-service/` | Small Python service with planted defects and one decoy file that must not be "fixed" |
| `graders/order-service-answer-key.md` | Planted defects and expected behavior; never shown to the agent under test |
| `run.sh` | Runs a scenario in a throwaway git repo with a headless agent and saves transcript and diff |

## Run

```bash
evals/run.sh full-harden                     # Claude Code, skill installed
evals/run.sh full-harden --without-skill     # baseline for comparison
evals/run.sh optimize-only --agent codex
evals/run.sh review-only --dry-run           # show what would run
```

Grade each result by giving a judge model the scenario's `expectations`, the answer key,
`transcript.txt` and `diff.patch`, and asking for met / not met with a quote as evidence
for each expectation. Report the score with and without the skill. Lift is what counts.

## When to re-run

- After any edit to `SKILL.md` or `references/`: all scenarios, at least 3 runs each (agent output varies).
- After editing the `description`: the trigger queries, judged on a held-out 40%.
- On a new model release: everything, including a smaller model.

Add a scenario whenever the skill fails in real use. Write it before fixing the skill,
confirm it fails, then fix.
