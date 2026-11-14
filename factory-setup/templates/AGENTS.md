# <<NAME>>: worker handbook
Rules for the worker and reviewers. Standing roles and merge rules: `docs/agents/OWNER-INSTRUCTIONS.md`.
Exact commands: `belt.conf` (`WORKER_CMD`, `REVIEWER_CMD`, `RISKY_REVIEWER_CMD`). Never invent a model or CLI.

## What this is
<<one paragraph: app, audience, platform, what "done" means for v1>>

## Build and test
<<exact commands, or "TBD by the first ticket">>
- Run checks yourself, fix failures, rerun (up to 5 rounds), then write the receipt.
- Quote paths with spaces. Prefix tools as needed (<<ENV notes>>).

## Architecture
<<2-8 lines on where logic, UI and tests live, or "undecided" until the first ticket decides>>

## Safety
- <<per risky area: the one rule, e.g. "data is deleted only after an explicit user confirmation">>
- Tests and runs use fakes/test data only: <<launch flag or fixture>>. Never real user data.
- Stage explicit paths, never `git add -A`. Fresh branch and worktree per ticket; never commit to main.
- Never weaken, skip or delete tests or checks to make them pass. Never invent results.

## Receipt (at most one screen)
Files changed; each check pass/fail; screenshots if UI; each acceptance criterion with evidence; open doubts.

## Docs
Keep `docs/` in sync with behaviour: <<list of docs>>. Issues: <<tracker + command>>.
