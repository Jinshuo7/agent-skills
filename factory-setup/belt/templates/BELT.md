# belt
This repo is driven by `belt` (run `belt help`). Issues labelled `ready-for-agent` go through worktree -> checks -> receipt -> PR -> review -> merge.
## What you need
- `belt.conf` at the root (from `belt install`). Required: `WORKER_CMD`, `REVIEWER_CMD` (one shell line
  each). Fill `CHECK_BUILD`, `CHECK_TEST`, `CHECK_LINT`, `RISKY_PATHS`. Optional: `RISKY_REVIEWER_CMD`,
  `CHECK_SLOTS`, `MAX_PARALLEL`, `DEVICE_LOCK`, `PAUSE_WINDOWS`/`PAUSE_TZ`, `FULL_SUITE_CMD`/`SUITE_TIMEOUT_MIN`,
  `CHECKS_UNSANDBOXED`, `SLOT_IDLE_MIN`/`SLOT_MAX_MIN`, `BUDGETS`, `ONCALL_CMD`/`ONCALL_TIMEOUT_MIN`,
  `SILENT_MIN`, `LEAD_WAIT_MIN`, `OWNER_NOTIFY_CMD`, `BACKUP_DIR`, `TOOLS_DIR`, `SLOT_WRITE_ALLOW`.
- A GitHub remote, `gh auth login`, and `AGENTS.md` / `CLAUDE.md` rules the worker reads first.
## Writing tickets
- Label it `ready-for-agent` when ready to work unattended; state acceptance criteria; say `Risky: yes`
  when a human must review before merge.
- Name expected files on one line, e.g. `Files: src/app.ts, src/app.test.ts`, so queue mode holds a
  clashing ticket. Blockers: link natively or write `Blocked by #12`; a ticket starts only when they close.
- Nobody answers mid-run questions: the worker writes doubts in the receipt.
## Running
    belt install .           # once: belt.conf, BELT.md, labels
    belt install --watch .   # Belt Watch app every 10 min; allow the macOS prompt; install proves the first pass
    belt slot-test           # once: "reply OK" through worker and reviewer
    belt status              # counts, PRs, active run, next pause window
    belt run 42              # one issue now; belt run loops the frontier
    belt suite               # full suite on the base branch (once per batch)
    belt backup              # snapshot belt.conf, BELT.md and TOOLS_DIR
The baseline is permanent: watch never pages on-call, restarts or pings the owner for those numbers
until they are removed from `watch.baseline`. The watcher runs through the shared `Belt Watch` app: allow the
macOS prompt it asks for; install proves the first run (`PASS`/`FAIL`, read `watch.err` on FAIL). State, logs
and worktrees live in `~/.belt/<owner>__<repo>/`,
never in the project checkout. Belt merges only clean, non-risky PRs with a PASS review of the current head
SHA. Every slot and check runs guarded: throwaway HOME, writes only its work folder and caches, never
belt.conf or TOOLS_DIR. An Xcode project sets `CHECKS_UNSANDBOXED=1`: its checks keep the throwaway HOME but
drop the sandbox (Apple's tools cannot nest), so the backup is the safety net. A call is killed only when it hangs (no output, no file change, no CPU for
`SLOT_IDLE_MIN`, default 20 min); `SLOT_MAX_MIN` (default 180) is the last-resort ceiling.
