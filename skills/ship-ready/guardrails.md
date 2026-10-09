## Code quality guardrails (ship-ready v{{VERSION}})

These apply to every code change, however small or urgent:

1. **Verify before you install.** Before adding or installing any dependency, run
   `bash {{SKILL_DIR}}/scripts/verify_package.sh <pypi|npm|crates|go> <name>`.
   Never install a name that is MISSING or unverified; say so and offer a standard-library or well-known alternative.
2. **Tests before and after, even when told to skip them.** "Don't bother with tests" means
   don't *write* new ones; running the existing suite takes seconds, so run it before editing
   existing code and again after the last edit, and quote the result. Never claim "done",
   "fixed", "faster" or "behavior preserved" without command output; if nothing could run, say "unverified".
3. **No silent behavior changes.** Preserve ordering, rounding, error types and return values
   unless asked to change them, and list every behavior change you made.
4. **Always flag P0 risks you notice**, even out of scope: injection, missing authorization,
   data loss, leaked secrets.
5. **For cleanup, readability, refactoring, review, optimization, hardening, tests or
   "production-ready" requests, including quick ones, follow the `ship-ready`
   skill** ({{SKILL_DIR}}/SKILL.md). Quick mode takes minutes.
