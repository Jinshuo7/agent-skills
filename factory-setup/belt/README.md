# belt
A universal conveyor belt for `ready-for-agent` issues: worktree -> worker -> checks -> receipt -> PR ->
reviewer -> merge, or hand-off to a human lead. Pure bash 3.2; needs `git`, `gh`, `jq`.
    belt install [--watch] <dir>   # belt.conf, BELT.md, labels; --watch adds launchd
    belt slot-test [project]       # send "reply OK" through every configured slot
    belt run [issue]               # one issue now, or loop the queue
    belt suite [--must-pass]       # full suite on the base branch (once per batch)
    belt watch [project]           # one on-call pass; belt unwatch <dir> removes it
    belt watch --baseline [project] # ignore today's open stuck/needs-owner issues, for good
    belt backup [project]          # snapshot belt.conf, BELT.md and TOOLS_DIR under BACKUP_DIR
    belt status                    # counts, open belt PRs, active run, next pause
`belt.conf` holds the project settings (see `templates/belt.conf`). `WORKER_CMD` and `REVIEWER_CMD` are
required: one shell line each, run with `bash -c` in the work folder with `BELT_PROMPT_FILE` and
`BELT_OUT_FILE` set. `RISKY_REVIEWER_CMD` reviews risky diffs; `ONCALL_CMD` is the fixer. State, logs and
worktrees live under `BELT_HOME` (default `~/.belt/<owner>__<repo>/`), never in the project checkout.
Tickets finish merged, `needs-lead`, `needs-owner` or `stuck`, never both claimed and finished.
Every slot and every check runs through `guard_exec`: a throwaway `$HOME`, no write outside its own work
folder (never the real home, `/Volumes`, `belt.conf` or `TOOLS_DIR`). An on-call restarts a ticket by
ending with `ONCALL: RESTART <n>`; belt runs the restart outside the sandbox. `belt backup` hardlinks
unchanged files, never `--delete`, and keeps the newest 14; `belt watch` runs it at most once a day.
Queue mode starts only frontier tickets; `Files:` clashes and open blockers hold one. `MAX_PARALLEL=0`
means no cap; checks run under `CHECK_SLOTS`; `PAUSE_WINDOWS`/`PAUSE_TZ` pause queue mode.
A model call is never killed for being slow (normal runs take 50-95 min): it is hung when for
`SLOT_IDLE_MIN` (default 20) minutes no output file grew, no file in its work folder changed and its
process tree used no CPU; `SLOT_MAX_MIN` (default 180) is a last-resort ceiling. `FULL_SUITE_CMD` runs on
the base branch under `SUITE_TIMEOUT_MIN`; a red base opens a `stuck` issue and is bisected.
`belt watch` finds stuck, over-budget and hung tickets, runs `ONCALL_CMD` under `ONCALL_TIMEOUT_MIN` with
the same idle test, and pings the owner only for real handoffs.
Safety is in code: no force-push, no `git add -A`, no `--admin`, no reset or clean in the project
checkout, risky changes never merge, and a merge needs a review of the PR's exact head SHA plus green
checks; a reviewer that changes its copy fails.
