# Standing instructions: how agents build <<NAME>>
> Owner directive, <<DATE>>. Replaces every earlier version.

## The owner
The person you build for: <<OWNER_PROFILE>> (how technical they are, how they want to be asked).
Involvement: <<LEVEL>>. Taste only: agents make engineering, process and merge decisions; ask the owner only
taste or product questions and human-only steps (<<e.g. device testing, store accounts, signing, payments>>).
Weekly: the same, plus a short weekly summary. Every decision: every merge waits for the head, who asks
the owner (`RISKY_PATHS="*"` in `belt.conf`). Ask one question at a time, using the head tool's question pop-up if it has one, recommended option first; plain language. Never hand the owner commands to run.

## Roles
Exact commands: `belt.conf` (`WORKER_CMD`, `REVIEWER_CMD`, `RISKY_REVIEWER_CMD`). Never invent a model or CLI.
1. Worker, <<WORKER>>: writes code and tests, runs checks, fixes its own failures and every FIX verdict.
2. Routine reviewer, <<REVIEWER>>: read-only review of routine changes.
3. Risky reviewer, <<RISKY_REVIEWER>>: read-only review of changes touching risky areas.
4. Head, <<HEAD>>: plans with the owner, writes tickets, decides risky merges from a summary, takes
   tickets the belt marks stuck or needs-lead. Does not watch or poll workers.
5. Gate, the belt: runs checks and merges routine changes by rule; risky ones wait for the head.

## Core rules
- One task per session; state lives in the tracker and docs, not chat. Long session: write a one-page handoff and stop.
- The head delegates detailed reading and decides from summaries and receipts.
- Receipts are at most one screen. The handoff (`NEXT-SESSION-HANDOFF.md`) is one page.
- Claims: label or note who works on a ticket; one worker, one branch, one worktree.
- Checks scale with the change: fast checks per ticket, the full suite once per batch and before a release.
  Workers may always edit test files; a ticket's "files that may change" never excludes tests.
- Local checks, then review, then remote CI. Only P1 and unmet acceptance criteria open a fix round; P2/P3 are
  posted and never block. A failed run is re-run only when it failed for infrastructure reasons, never blindly.
- Batches are a judgement, never a number: small when changes overlap or touch risky paths, and a red batch is
  bisected, never guessed.
- Every stage writes timings. A stage over its budget reaches the owner the same hour; the weekly line shows
  runner hours and waste.
- The lead stops stuck or wasteful work itself (a stuck CI run, a stale worker); the owner hears results and real
  decisions only.
- Independent work runs in parallel: reviews, docs and model work never wait for the simulator or CI.
- Infrastructure work never blocks a release; if a speed-up is not ready, ship on the old path.
- Owner feedback is a checklist: every owner point becomes a ticket or a written answer, and the release note shows
  that table (point → ticket → status).

## Tickets contain
Goal; files that may change; acceptance criteria; what not to touch; checks that prove it; risky or not.

## Risky areas (strong review; the head decides the merge)
<<RISKY_AREAS with one blocking rule each>>
A risky PR merges only after: <<RISKY_REVIEWER>> review of the exact head SHA with no blocking finding, and <<HEAD>> reading the summary. A review that did not find the head SHA or saw an empty diff FAILS, never "clean".

## Merging
Always: checks green on current head; diff touches only the ticket's files; no test or gate removed, skipped or weakened; merge commit pinned to the head SHA.

## Safety
Fresh branch per ticket; never commit to main; never reset/stash/force-push; stage explicit paths; tests use fakes only; never invent results; owner-only: <<store submission, signing, spending money, anything outside the repo>>.

## Decisions the docs do not settle
Engineering/process: decide and note it. Product/taste: ask the owner one pop-up question with a recommended answer; keep working on anything independent.

## Model reference
Team and exact commands: `belt.conf`. How they were chosen: `docs/kickoff/decisions.md` (and `trial.md` if a trial ran). Re-tune with /factory-setup when a plan or price changes; change `belt.conf` only when the owner asks. Keep default thinking levels.
