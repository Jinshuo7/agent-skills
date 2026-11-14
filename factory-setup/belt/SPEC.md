# belt: spec for the implementer

Build a universal "conveyor belt" in this folder: it takes `ready-for-agent`
GitHub issues of ANY project through: worktree -> worker builds -> checks -> receipt -> PR -> reviewer
-> merge or hand to lead. Pure bash 3.2 (macOS /bin/bash: NO associative arrays, NO `wait -n`,
NO `timeout`, NO mapfile) plus `git`, `gh`, `jq`. No project-specific anything.
Prefer simple, readable code; small functions; every external call checked; `set -u`, handle failures.

## Files
- `belt` : dispatcher (`run [issue]`, `suite [--must-pass]`, `watch`, `slot-test [project]`, `status`, `install [--watch] <project-dir>`, `unwatch <project-dir>`, `help`). Resolves its own dir through symlinks.
- `lib/common.sh` : config load, slot runner, logging, labels, locks, pause-window check, risky-path test, timings, helpers.
- `lib/ticket.sh` : the per-ticket pipeline (stations 1-10).
- `lib/review.sh` : pluggable review of an exact head SHA, with a read-only guard.
- `lib/suite.sh` : the full suite on the base branch, its state, the release gate and bisect.
- `lib/watch.sh` : the on-call pass (`belt watch`), problem keys, owner pings and merge-gate resume.
- `lib/guard.sh` : `guard_exec`, the one choke point every slot and check runs through (throwaway HOME; sandbox, except check and suite when `CHECKS_UNSANDBOXED=1`).
- `lib/backup.sh` : `belt backup`, the config/tools snapshots and their pruning.
- `worker-rules.md` : generic rules prepended to every worker prompt (see below).
- `templates/belt.conf` : commented config template. `templates/BELT.md` : README for projects (<= 30 lines).
- `tests/selftest.sh` : offline tests for pure functions (pause windows, risky globs, config load, status line trimming, slots, reviewer guard, caps, timing stamps, watch keys, suite state) plus the slot guard, backup snapshots and the on-call restart verdict. Must pass.

## Where things live
- Run from the project directory (or set `BELT_PROJECT=/path`). Project = a git checkout with `belt.conf` at its root.
  Paths contain spaces: quote everything.
- State and logs: `$BELT_HOME` (default `~/.belt`) / `<owner>__<repo>` / `<issue>/` (log, receipt.md, files, verdicts) and
  `.../worktrees/<issue>`. Worktrees live OUTSIDE the project. Belt never writes in the project checkout except
  `git fetch` and `git worktree add/remove` metadata, and `belt install`.
- Repo slug from `gh repo view --json nameWithOwner`, or `REPO` in belt.conf.

## belt.conf (sourced as shell; one KEY="value" per line; every key optional with a default, except the slots)
BASE_BRANCH (default: repo default branch), CHECK_BUILD, CHECK_TEST, CHECK_LINT (shell commands run in the worktree;
empty = skip), RISKY_PATHS (space-separated globs; `*` matches across `/`; trailing `/` = whole folder; empty = nothing risky
by path), MAX_PARALLEL (default 0 = no cap; a positive number caps how many tickets run at once),
CHECK_SLOTS (default CPU count, or 1 when CHECKS_UNSANDBOXED=1 since each Xcode check boots a simulator; how many of the CHECK_BUILD/TEST/LINT commands run at once), CHECK_START_GAP_SEC (default 0, or 20 when CHECKS_UNSANDBOXED=1: minimum seconds between two check starts across slots), DEVELOPER_DIR (when unset and `xcode-select -p` is the Command Line Tools while Xcode is installed, belt exports the Xcode path), DEVICE_LOCK (path of a lock; when set, the check
commands run holding it, via a mkdir lock with stale detection by pid), WORKER_CMD and REVIEWER_CMD (required, no defaults: one
shell command line each, run with `bash -c` inside the worktree / the review worktree, stdin from /dev/null, with
`BELT_PROMPT_FILE` (the prompt, a file in TICKET_DIR) and `BELT_OUT_FILE` (an empty file in TICKET_DIR the command may write its
answer to) in the environment), RISKY_REVIEWER_CMD (optional, same contract; used instead of REVIEWER_CMD when the diff is risky),
PAUSE_WINDOWS (default empty = never pause; space-separated entries like `Mon-Fri@09:00-12:00` `Sat@10:00-11:00`, end time
exclusive), PAUSE_TZ (default empty = machine local time; any TZ name; an invalid PAUSE_WINDOWS makes belt refuse to start),
CHECK_WAIT_MIN (default 15: minutes to wait for remote CI on the PR), REPO, FULL_SUITE_CMD (default empty = off: the slow whole-project suite, run once per batch on the base branch, never per ticket), SUITE_TIMEOUT_MIN (default 120: hard cap for one suite run; exit 124 is infra = UNKNOWN), SLOT_IDLE_MIN (default 20: a worker/reviewer/risky-reviewer/on-call call that makes no progress this long is hung and killed; a kill is a failed call with one retry), SLOT_MAX_MIN (default 180: last-resort ceiling for one such call), ONCALL_CMD (default empty; required for `belt watch`, same slot contract), ONCALL_TIMEOUT_MIN (default 30, the same idle test applies), SILENT_MIN (default 45: a live ticket with no log or output-file change, no work-folder change (for a custom runner, also no change in its processes' working folders inside the project) and under SILENT_CPU_CS_MIN of CPU across two samples this long, and no CI in progress, is hung/silent; a custom-runner ticket stays watched until its run ends, even if its label is removed), BATCH_BRANCH_PREFIX (default `batch/`), BATCH_CI_WORKFLOW (default `CI`) and BATCH_CI_MAX_MIN (default 240) drive the batch CI watch: every watch pass reads the newest run on each open batch PR; a failed job with no failed step is an infrastructure failure, re-run once; a real failure, a cancelled run, an overdue run, a second infrastructure failure or an hour of unreadable GitHub alerts the owner once and is never re-run. SILENT_CPU_CS_MIN (default 20: hundredths of a second of CPU a minute that count as working; a hung worker uses about 7), CONFLICT_MIN (default 10: a merge-conflicted belt PR with no CI run this long and mergeable_state=dirty is conflict:, not a wait), LEAD_WAIT_MIN (default 120: a risky PR waiting on the lead longer gets one owner ping), OWNER_NOTIFY_CMD (default: macOS `osascript` notification; any shell line, message in `$BELT_MESSAGE`), CLAIM_LABEL (default `claimed:belt`: the label a claimed ticket wears; watch keys, claim clearing and the on-call playbook use it), BRANCH_PREFIX (default `belt/`: the ticket branch prefix, always used with one trailing slash), TICKET_LOG_CMD (default empty = belt's own ticket log: a shell line printing the ticket's log path, issue number in `$BELT_ISSUE`), TICKET_ALIVE_CMD (default empty = belt's `ticket.lock` holder test: a shell line exiting 0 while the ticket's run is alive, issue number in `$BELT_ISSUE`; an optional numeric first line names the run's process for CPU sampling), TICKET_RESTART_CMD (default `belt run <n>`: a shell line that restarts the ticket in the background, issue number in `$BELT_ISSUE`; the watch pass, never the on-call, runs it after an `ONCALL: RESTART <n>` verdict), ONCALL_EXTRA_RULES (default empty: text appended to the on-call playbook), SLOT_WRITE_ALLOW (default empty: extra absolute paths a slot may write, space-separated), TOOLS_DIR (default empty: space-separated folders snapshotted by `belt backup`, and write-denied to every slot and check), BACKUP_DIR (default empty: where `belt backup` writes `BACKUP_DIR/<owner>__<repo>/<YYYYMMDD-HHMM>/`; empty means no backup), CHECKS_UNSANDBOXED (default 0; 1 drops only the sandbox for check and suite commands whose build tool cannot nest, the throwaway HOME stays; Xcode projects must set 1), BUDGETS (default empty = no budget alerts; space-separated `stage=minutes`, stages `impl review fix ci batch-ci ticket`), and the planned key BATCH
(see "SPEC changes" at the end). Reload config at the
start of each ticket. `belt run` / the queue refuse to claim any ticket while a slot is unset, naming the missing key.

## Stations (per issue N; `belt run N` runs one now, ignoring pause windows; `belt run` loops the queue)
Queue = open issues labelled `ready-for-agent` and NOT labelled `claimed:belt`, `stuck`, `needs-lead`, `needs-owner`; oldest first.
Queue mode: one `belt run` per project at a time (mkdir lock), start frontier tickets as background subshells (every one when
MAX_PARALLEL=0, otherwise at most MAX_PARALLEL), poll with `sleep 5` and `jobs`, finish when queue empty and all done.
Re-fetch queue and re-evaluate the frontier every round, so tickets start as their blockers close.
Frontier: a ticket may start only when every blocker is closed. Blockers come from GitHub's native links
(`gh api repos/OWNER/REPO/issues/N/dependencies/blocked_by`, a JSON array of `number`/`state`; HTTP 404 = no links) and from body
lines like `Blocked by #12`, `Blocked by: #12, #14` or `- Blocked by #12` (case-insensitive; look up each named issue's state).
An open blocker blocks. If either source cannot be read (API error other than 404), do not start that ticket this round and log why.
File clashes: a body line starting `Files:` names the files a ticket touches (comma/space separated, and/or backticked paths
containing `/` or an extension). A frontier ticket whose named files overlap a running ticket's named files is held (logged)
until that ticket finishes. A ticket that names no files is never held.
Pause windows (queue mode only, when PAUSE_WINDOWS is set): belt waits instead of starting tickets during the configured
windows, interpreted in PAUSE_TZ (default: machine local time). An empty PAUSE_WINDOWS never pauses.
Test hooks: env `BELT_NOW="YYYY-MM-DD HH:MM"` overrides the clock (interpreted in PAUSE_TZ), `BELT_NO_SLEEP=1` makes waits return instead of sleeping,
`BELT_TIME_SCALE=<n>` divides every timeout (60 turns one minute into one second), `BELT_SUITE_FOREGROUND=1` runs `belt suite` in the foreground,
and `BELT_LAUNCH_AGENTS` / `BELT_NO_LAUNCHCTL=1` redirect and disable launchd in tests.
1. Claim: add label `claimed:belt` (create missing labels first: claimed:belt, stuck, needs-lead, needs-owner, ready-for-agent). Comment "belt picked this up".
2. Worktree: `git fetch origin`; branch `belt/<N>` from `origin/<BASE>` into `worktrees/<N>`. If the worktree/branch/PR already exists, resume
   (reuse the worktree; if a PR for the branch exists skip to station 7).
3. Implement: write the prompt to `TICKET_DIR/prompt.txt` and run `WORKER_CMD` with `bash -c` (via `slot_run`) with the worktree
   as cwd, stdin `/dev/null`, `BELT_PROMPT_FILE` = that file and `BELT_OUT_FILE` = `TICKET_DIR/worker-out.txt`; stdout+stderr to
   `TICKET_DIR/worker.log`.
   Prompt = contents of `worker-rules.md` + ticket title/body (from `gh issue view --json title,body,comments`, last 5 comments) + OUT_DIR path +
   "read AGENTS.md / CLAUDE.md in the repo first if present". After it ends: a nonzero exit fails the station; if HEAD of the worktree moved (worker committed) -> fail with that reason.
4. Checks: run CHECK_BUILD, CHECK_TEST, CHECK_LINT in order in the worktree, each under the CHECK_SLOTS counting semaphore (lock
dirs under `BELT_HOME`, wait and retry) and then under DEVICE_LOCK if set; record PASS/FAIL/SKIPPED each; first
   failure stops. They run through `guard_exec check`: sandbox and throwaway HOME, no harness env (see "Slot guard and backup"); an Xcode project sets `CHECKS_UNSANDBOXED=1`, so its checks keep the throwaway HOME but run without the sandbox. On failure: retry station 3 once with the last 30 log lines of the failing check appended; a second failure -> station 10.
   If the worker wrote `OUT_DIR/nochange.txt` -> comment its text on the issue, label `needs-owner`... NO: label `stuck`, remove `claimed:belt`, stop.
5. Receipt: if the worker did not write `OUT_DIR/receipt.md`, belt writes a minimal one itself. Belt always appends a "Checks" table from the real results
   (worker claims are not trusted). Receipt <= 40 lines (truncate).
6. Commit/push/PR: file list = `git status --porcelain` in the worktree, minus anything matching: `.env*`, `*.pem`, `*.key`, `*secret*`, `.belt/`, `node_modules/`,
   `.DS_Store`. `git add -- <each explicit path>` (NEVER `-A`, `.`, or `-u`). If nothing to stage -> treat as nochange. Commit message from
   `OUT_DIR/commit.txt` or `Fix #N: <issue title>`; `git commit` with `-c user.name/email` unchanged from the repo config (do not set). Push with plain
   `git push -u origin belt/<N>` (NEVER force; on rejection fail the ticket). `gh pr create --base <BASE> --head belt/<N> --title ... --body receipt + "Closes #N"`.
7. Review (lib/review.sh): create a detached review worktree at the PR's exact head SHA (`gh pr view --json headRefOid`), then run
   the reviewer slot with `bash -c` (via `slot_run`) inside that worktree, stdin `/dev/null`, `BELT_PROMPT_FILE` = the review prompt in
   TICKET_DIR, `BELT_OUT_FILE` = `TICKET_DIR/verdict.txt`; stdout goes to `TICKET_DIR/reviewer-out.txt`. Compute risk first (fail closed:
   uncomputable risk = risky) and use RISKY_REVIEWER_CMD when the diff is risky and that key is set, else REVIEWER_CMD; routine diffs
   always use REVIEWER_CMD. Record which reviewer ran in the ticket log. Prompt: review `git diff origin/<BASE>...HEAD` for
   correctness, safety, missing tests; list findings as `P1: ...` (must fix) or `P2: ...` (minor) one per line, at most 12 lines total, then a last line exactly `VERDICT: PASS`
   or `VERDICT: FIX`. The answer is `BELT_OUT_FILE` when non-empty, else the captured stdout.
   Read-only guard: record the review worktree HEAD and `git status --porcelain --untracked-files=all` before the reviewer; if either differs
   afterwards -> review failed with `reviewer changed files` (also fail closed when either cannot be read).
   Fail closed: if the SHA is unknown, the checkout is not at the SHA, the diff is empty, the reviewer exits nonzero or changes files ->
   review failed (retry once, then station 10); post nothing. The verdict is read from the last non-empty line that is not a code fence, ignoring `*`, `_` and backticks; it may end a sentence (`... VERDICT: PASS`). When there is no answer or that line does not end in a verdict, rerun
   the reviewer once first; the read-only checks run after every attempt, and a second bad answer still fails closed. Never post a
   failed review.
   Post as a PR comment: `### Review of <full 40-char head SHA>` + the lines, <= 15 lines total. A P1 line exists -> findings.
   A `VERDICT: FIX` (or any P1 line) sends the ticket back to the worker (station 3) for one fix round, then re-run 4-7; still P1 -> station 10.
8. Merge gate. Merge ONLY if ALL: PR not risky; local checks all PASS or SKIPPED; no P1 in the review of the CURRENT head SHA; remote CI (if any checks exist on the PR) all green
   (poll `gh pr checks` every 30s up to CHECK_WAIT_MIN; no checks reported = fine; pending after the wait -> leave PR open, label `needs-lead`, comment why).
   Then `gh pr merge <PR> --squash --match-head-commit <sha>`. On success remove `claimed:belt`, comment on the issue "merged in PR #", close happens via "Closes #N".
9. Risky = any changed file (from `git diff --name-only origin/<BASE>...HEAD`) matches RISKY_PATHS, OR issue body contains a line `Risky: yes` (case-insensitive).
   Risky PR: after a clean review, comment, label PR and issue `needs-lead`, remove `claimed:belt`, STOP. Never merge it, not even with --admin. Never use `gh pr merge --admin`.
   Rate limits: when a worker or reviewer call fails and its output (stdout, stderr or out file) mentions a rate/usage limit (`429`,
   `rate limit`, `rate_limit`, `too many requests`, `usage limit`, `quota`, `try again later`, `limit reached`), wait and retry the
   same call (60s, doubling, at most 30 min between tries, give up after 6h total and mark the ticket stuck). `BELT_NO_SLEEP=1` makes
   test waits instant. Other failures behave as before.
10. Failure: any failed station -> one automatic retry of that whole ticket stage as described; then label issue `stuck`, remove `claimed:belt`, comment <= 5 lines with the reason and
    the log path. A ticket must never leave the issue both `claimed:belt` and finished.
Owner steps: if the worker writes `OUT_DIR/owner-steps.txt` (one plain sentence per line, e.g. "Create an Apple developer account"), belt opens one issue per line
(title = the sentence, trimmed to 80 chars, label `needs-owner`, body "Needed for #N", created only if no open issue with the same title exists).
Also if a station needs a human only action belt itself can detect (e.g. `gh auth` failure), open a `needs-owner` issue the same way.

## Hard caps and timing stamps (shipped)
- Hang, not elapsed time: measured worker runs take 50-95 min, so time alone never kills a call. Every worker, reviewer,
  risky-reviewer and on-call call run through `slot_run_retry` is watched by `slot_run_guarded`. A call is HUNG when, for
  `SLOT_IDLE_MIN` (default 20) minutes, its stdout/stderr/out files have not grown AND no file in its work folder changed (newest
  mtime under the dir, ignoring `.git`) AND its process tree used no CPU (sum of `ps -o time=` unchanged between checks). It is then
  killed with its whole tree and counts as a failed call: the log says `slot hung: no output, no file change, no CPU for N min`, the
  call is retried once from an identical tree, and the ticket stage fails as usual after that. `SLOT_MAX_MIN` (default 180) is a
  separate last-resort ceiling (`slot hit the hard ceiling of N min`). The same idle test decides `silent:` in `belt watch`.
- `stamp <stage> <start|end|stuck>` (in `lib/common.sh`) writes one line to `<ticket dir>/timings.tsv`:
  `<epoch>\t<issue>\t<stage>\t<event>`. Belt calls it around `impl`, `review`, `fix`, `ci` and `ticket`; the suite uses the same
  helper for `batch-ci` in the state dir. Every start gets its end or `stuck`.
- `BUDGETS` (default empty = no alerts) is read by `belt watch`: an open stage past its budget becomes a `budget:` problem.

## Full suite per batch (shipped)
- `CHECK_BUILD/TEST/LINT` stay the fast per-ticket checks. `FULL_SUITE_CMD` (default empty = off) is the slow whole-project suite.
- `belt suite [project]`: if the base branch has commits newer than the last green full-suite SHA (stored with the result in
  `BELT_HOME/<slug>/suite.state`) and no run is live, run `FULL_SUITE_CMD` in a clean disposable worktree of the base branch under
  `SUITE_TIMEOUT_MIN` (default 120). The run is detached with its own lock/pid file (`suite.lock`); a watch pass only starts it or
  reads its result, never waits on it.
- Green records the SHA the suite actually tested (the worktree's SHA at start). Red opens, once per SHA, an issue
  `Base branch red since <sha>: full suite failed` labelled `stuck` with the log tail.
- Exit 124 (timeout) is infrastructure: record UNKNOWN, open no red issue, bisect nothing, and ping the owner once if it happens
  twice in a row.
- `belt suite --must-pass` exits nonzero unless the current base SHA is green (the release gate).
- `belt watch` calls `belt suite` on every pass.
- Bisect runs only in a disposable worktree under `BELT_HOME`, with a trap that runs `git bisect reset`, at most 12 steps, never in
  the project checkout. A watch pass never waits on it: it dispatches `belt __bisect` detached under its own `bisect.lock`, writes
  `bisect.culprit`, and a later pass comments the culprit commit and its PR on the red issue; the on-call sees the result.

## On-call fixer: belt watch (shipped)
- `belt watch [project]` is one pass: mkdir lock (never overlaps), one summary log line. It exits nonzero only when it
  cannot read `belt.conf`; that pass alerts the owner itself and fails. Run it every 10 minutes via
  `belt install --watch <dir>` (writes `~/Library/LaunchAgents/com.belt.watch.<owner>.<repo>.plist`, StartInterval 600) and remove it
  with `belt unwatch <dir>`. Plain `belt install <dir>` never installs the agent.
- On macOS the launchd job must not run `/bin/bash` directly: privacy denies a plain launchd shell access to an external
  volume, so every pass failed to read `belt.conf`, logged to `watch.err`, returned 0 and nobody was told. Install creates one
  machine-wide, ad-hoc-signed applet at `~/.belt/bin/Belt Watch.app`, only when it is missing (rebuilding changes its identity
  and loses the macOS grant). The plist runs `Belt Watch.app/Contents/MacOS/applet`; the applet runs
  `Contents/Resources/run-watch.sh`, which has no project details and reads `BELT_WATCH_BELT`, `BELT_WATCH_PROJECT`,
  `BELT_WATCH_OUT` and `BELT_WATCH_ERR` from the plist's `EnvironmentVariables`. macOS may show a permission prompt for
  "Belt Watch" the first time; it must be allowed. After loading, install kickstarts one pass and waits up to 90 s for
  `watch: config loaded` in `watch.log`, then prints `PASS: first automatic run read its config` or
  `FAIL: first automatic run could not read its config; see <watch.err>` and exits nonzero on FAIL. Re-installing over an
  existing plist unloads the old job and loads the new one; the app itself is never rebuilt.
- A pass logs `watch: config loaded` right after `load_config` succeeds. A pass that cannot read `belt.conf` sends its own
  `osascript` notification (OWNER_NOTIFY_CMD is unavailable without config), at most once an hour via a marker file under
  `$BELT_HOME/watch-config/`, and exits nonzero.
- Problems, each with a stable key:
  - issue labelled `stuck`, or `needs-lead` on a NON-risky PR: `stuck:<n>`, `lead:<n>`;
  - open stage in `timings.tsv` over its `BUDGETS` budget: `budget:<n>:<stage>:<start>`;
  - live ticket whose log has not changed for `SILENT_MIN` (default 45) while its PR has no CI run in progress or queued: `silent:<n>`;
  - issue still labelled `CLAIM_LABEL` (default `claimed:belt`) whose ticket has no live holder and nothing changed for `SILENT_MIN` (the recovery
    chain dead-ended after a kill or failed restart): `stale:<n>`;
  - open belt PR whose head has had no CI run for `CONFLICT_MIN` (default 10) and `mergeable_state` is `dirty` (GitHub starts no
    pull_request CI on a conflicted PR, so this is not a wait; `silent:` is suppressed for the same PR): `conflict:<n>`;
  - red base branch from the full suite: `red:<sha>`.
- A project with its own ticket runner sets `CLAIM_LABEL`, `BRANCH_PREFIX`, `TICKET_LOG_CMD`, `TICKET_ALIVE_CMD` and `TICKET_RESTART_CMD`.
  Then `silent:` and `stale:` discover tickets from open issues with `CLAIM_LABEL` (no `ticket.lock` is needed), the idle test uses the log
  mtime, the log's work folder and a CPU sample when the alive command prints a pid, and the on-call restarts it by ending with
  `ONCALL: RESTART <n>` (belt runs `TICKET_RESTART_CMD`). `ONCALL_EXTRA_RULES` is appended to the playbook. `belt watch` and `belt drill` create the labels they read
  (claim label, `stuck`, `needs-lead`, `needs-owner`; the drill also creates `belt-drill`), so plain `belt install` is not required.
- `watch.seen` means "currently being handled": a key is removed when its condition clears, so a returning problem re-arms.
  Persistent `stuck:`, `silent:`, `budget:`, `stale:` and `conflict:` keys are retried every pass (they bypass `watch.seen`) until
  the per-issue attempt cap hands them to the owner.
## Watcher baseline (shipped)
- Adding the watcher to an existing project must not page anyone for work that predates it. `belt watch --baseline [project-dir]`
  writes the numbers of every currently open `stuck` and `needs-owner` issue to `BELT_HOME/<owner>__<repo>/watch.baseline`
  (one number per line, sorted). Every later pass ignores those numbers for `stuck:`, for any key about that issue's PR
  (`lead:`, `silent:`, `stale:`, `conflict:`, `budget:`) and for the `needs-owner` ping, so no on-call call, no restart and no
  owner ping happens for them. The list is permanent: an issue stays ignored until its number is removed from the file
  (delete the file to re-arm everything). Issues opened later are not in the file and are handled normally.
  `belt install --watch` writes the baseline automatically when no baseline file exists yet, and keeps an existing one.
- `belt drill` closes the `needs-owner` issue its own `OWNER` verdict opened, using the number `gh issue create` printed
  (an issue list is search-indexed and can miss an issue created a second ago), and prints `FAIL` when its own owner issue is
  still open after cleanup.
- For each new key, run `ONCALL_CMD` once (slot contract; same prompt/out files, and `slot-test` covers it when set), one at a time, in
  the project checkout, under `ONCALL_TIMEOUT_MIN` (default 30). Prompt = the problem, the log tail, `belt status`, and this playbook:
  a dead or hung ticket clears `stuck` and ends with `ONCALL: RESTART <n>`, leaving `CLAIM_LABEL` (default `claimed:belt`) and every process alone: its sandbox cannot see processes, so belt stops the old run (only on a `silent:` problem), clears the label and restarts the ticket outside it, and the on-call never runs `TICKET_RESTART_CMD` itself. A later pass checks the restart: a live run with a moved log, or a closed issue, or new work on the PR; anything else opens a needs-owner issue and alerts the owner;
  for `conflict:` merge the base branch into the PR branch (never rebase/force-push), resolve and push; re-run remote CI only on
  an infrastructure failure; clear a stale `CLAIM_LABEL` with no live run; for `red:` never run a
  bisect yourself; a normal wait (CI queued or running) changes nothing. Then `ONCALL_EXTRA_RULES` when set. Never merge a
  risky PR, never force-push, never touch secrets. Last line exactly `ONCALL: FIXED`, `ONCALL: WAITING`, `ONCALL: RESTART <n>`
  or `ONCALL: OWNER <one sentence>`. A `RESTART` whose `n` is not the issue being handled is ignored.
- A sandboxed on-call cannot restart a ticket (the child would inherit the sandbox), so belt does it: the watch pass (outside
  the sandbox) clears the dead holder's `CLAIM_LABEL` and runs `TICKET_RESTART_CMD` (default `belt run <n>`) detached. Killing
  a hung process tree stays allowed to the on-call.
- Belt posts the on-call's last 5 lines on the issue. At most 2 on-call attempts per issue (counted in BELT_HOME); the call that
  decides a restart is counted before it runs, so the 3rd time opens `needs-owner` (`#n keeps failing: <reason>`) and pings the
  owner instead of restarting.
- `OWNER ...` or no verdict opens a `needs-owner` issue (existing helper) and pings.
- A non-risky `needs-lead` PR whose CI has since completed green: remove `needs-lead` and resume the merge gate from the stored clean
  review (`review-sha`, `review-p1`, `checks.tsv`), with no model call.

## Owner ping (shipped)
- `OWNER_NOTIFY_CMD` (default: macOS `osascript -e 'display notification ...'`) is any shell line; belt sets `$BELT_MESSAGE`.
- `belt watch` pings once per key for: a new `needs-owner` issue (title), a risky PR waiting on the lead longer than `LEAD_WAIT_MIN`
  (default 120), and an on-call that ended `OWNER` or without a verdict. It never pings for normal waits or fixed problems.

## Slot guard (shipped)
- Model slots (not checks) may not exec a browser (Chrome, Chromium, Edge, Brave, Firefox, Playwright or Puppeteer builds): under the
  throwaway HOME it finds no keychain and puts a "Keychain Not Found" prompt on the owner's screen.
- Every model slot (worker, reviewer, risky reviewer, on-call, `slot-test`) runs through `slot_run` -> `guard_exec <role> <dir> <cmd>`;
  check, suite and bisect commands go through `guard_exec check`. There is no opt-out key and no env var for a slot.
- The real home comes from the passwd entry (`eval echo "~$(id -un)"`), never `$HOME`. Each call gets a throwaway `HOME` under
  `$TMPDIR`, removed after the call, and exports `PI_CODING_AGENT_DIR`, `GH_CONFIG_DIR`, `GIT_CONFIG_GLOBAL`, `CLAUDE_CONFIG_DIR`,
  `CODEX_HOME` from the real home. Checks get no harness env (no `PI_CODING_AGENT_DIR`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME`); they
  keep `GIT_CONFIG_GLOBAL` and the throwaway HOME.
- GitHub access belongs to the on-call slot only. The throwaway HOME has no keychain, so before replacing HOME belt reads the token
  with `gh auth token` using the real home (a failed lookup is ignored). Only the on-call role gets `GH_TOKEN` from it, plus git's
  gh credential helper through the environment form. The real git config has an osxkeychain helper that hangs on `store` under the
  throwaway HOME, so the first entry resets the helper list with an empty value: `GIT_CONFIG_COUNT=2`,
  `GIT_CONFIG_KEY_0=credential.helper`, `GIT_CONFIG_VALUE_0=''`, `GIT_CONFIG_KEY_1=credential.helper`,
  `GIT_CONFIG_VALUE_1='!gh auth git-credential'`. Every slot, whatever the role, also exports `GIT_TERMINAL_PROMPT=0` so git never
  waits on a prompt. Workers, reviewers and checks have `GH_TOKEN` and `GITHUB_TOKEN` removed and no
  such git config injected, so they have no GitHub access; belt itself does every `gh` write and every push. The token is never
  printed and never written to a file.
- The same missing keychain means a slot cannot sign for a physical Apple device, so local checks build for the simulator. An Xcode project must set `CHECKS_UNSANDBOXED=1` and export `DEVELOPER_DIR` in `belt.conf`. Apple's compiler and asset tools start their own sandbox and refuse a nested one, so those checks keep the throwaway HOME but have no sandbox: a test naming an absolute real path is not blocked, and `belt backup` is the safety net.
- On macOS `sandbox-exec` allows default, denies `file-write*` under the real home and `/Volumes`, then re-allows only: the slot
  dir, its git common dir (worker, on-call and checks; reviewer roles do not get it), the dirnames of `BELT_PROMPT_FILE` and
  `BELT_OUT_FILE`, the real `~/.pi`, `~/.claude`, `~/.codex`, `~/.cache`, `~/.npm`, `~/.swiftpm`, `~/.cargo`,
  `~/Library/Caches`, `~/Library/Developer`, `~/Library/Logs` and each `SLOT_WRITE_ALLOW` path. Checks get none of the agent dirs.
- A final deny, placed last, covers `belt.conf` (the slot dir's and the project checkout's, always), `~/Library/LaunchAgents`,
  `~/.appstoreconnect`, every `TOOLS_DIR`, `BELT_HOME` except the slot/ticket dirs, the git common dir's `hooks` and
  `config`, and, for every role that may not write the common dir (reviewers), the whole common dir, so no slot can plant a
  hook, set `core.hooksPath`, move refs or rewrite the shared index. `~/.ssh` is write-denied except `known_hosts` and
  `known_hosts.old` (the .ssh deny comes first, and git over ssh still reads its private keys); `~/.appstoreconnect` is also
  read-denied.
- "Already sandboxed" is detected by trying it: `sandbox-exec -p '(version 1)(allow default)' true`. Only a failure whose stderr
  names `sandbox_apply: Operation not permitted` counts as nested; only then does the command run directly, still with the throwaway
  HOME. Any other probe failure (or no `sandbox-exec`) means the sandbox is broken: the slot refuses to run with a clear error (fail
  closed). Xcode cannot run under any sandbox on macOS: Apple's compiler and asset tools start their own sandbox and nesting is
  refused (even an empty profile fails with `deny forbidden-sandbox-reinit`), so `xcodebuild` and `swift build` always fail in a
  check. An Xcode project must set `CHECKS_UNSANDBOXED=1`: those checks keep the throwaway HOME and have no sandbox, so a test
  naming an absolute real path is not blocked, and the backup is the safety net.
- Project wrappers on PATH keep working: they see `PI_CODING_AGENT_DIR` and can exec the real agent.

## Backup (shipped)
- `belt backup [project-dir]` snapshots `BACKUP_DIR/<owner>__<repo>/<YYYYMMDD-HHMM>/` with `rsync -a --link-dest=<previous>`.
  It never passes `--delete` and never touches older snapshots, except keeping the newest 14.
- Every snapshot includes the project's `belt.conf` and `BELT.md` (when present) and each `TOOLS_DIR`.
- Excluded everywhere: `*.env`, `*.env.*`, `.env`, `.env.*`, `.npmrc`, `.netrc`, `.git-credentials`, `*.p8`, `*.pem`,
  `.credentials*`, `.runner`, `asc-secrets/`, `_work/`, `_diag/`, `*.log`, `worktrees/`.
- A `TOOLS_DIR` that is missing or empty when a previous snapshot had it: no pruning, and one deduped owner ping
  (`backup:<owner>__<repo>`) because the tools may be gone.
- `belt watch` runs it at most once per 24 h (marker `BELT_HOME/<owner>__<repo>/backup.last`). A failure or an empty
  `BACKUP_DIR` produces one deduped owner ping. `BACKUP_DIR` sharing a volume with a `TOOLS_DIR` only warns.
- The backup runs outside the sandbox: belt itself does it, no model.

## Commands
- `belt run [issue]`, `belt suite [--must-pass] [project-dir]`, `belt watch [--baseline] [project-dir]`, `belt slot-test [project-dir]`, `belt status`,
  `belt backup [project-dir]`, `belt install [--watch] <project-dir>`, `belt unwatch <project-dir>`.
- `belt slot-test [project]`: for each slot (worker, reviewer, risky-reviewer when RISKY_REVIEWER_CMD is set, on-call when ONCALL_CMD is set),
  run it in a temp dir with a prompt file saying "Reply with exactly the word OK and nothing else.
  Do not edit any files."; pass if `BELT_OUT_FILE` or stdout contains `OK`; print one line per slot (`PASS`/`FAIL` + last 3 lines of output on
  fail); exit nonzero if any fails. Each call is limited to 180s (background-and-kill; macOS has no `timeout`).
- `belt status`: at most 10 lines, plain: project slug; counts of ready-for-agent / claimed / needs-lead / stuck / needs-owner issues; open belt PRs (number + state); whether a run is active; next pause window when PAUSE_WINDOWS is set.
- `belt install [--watch] <dir>`: copy `templates/belt.conf` to `<dir>/belt.conf` and `templates/BELT.md` to `<dir>/BELT.md`, never overwrite an existing file (print "exists, skipped");
  if `<dir>` has a GitHub remote, create the labels (idempotent). `--watch` installs the Belt Watch applet and its launchd job
  (see "On-call fixer"), proves the first automatic pass read `belt.conf` (PASS/FAIL, nonzero on FAIL), and writes the
  `watch.baseline` snapshot (see "Watcher baseline") when no baseline file exists. Does not commit. Prints what to do next.
- `belt unwatch <dir>`: unload and remove the launchd watch agent for that project (no-op when absent; the shared `Belt Watch.app` stays).

## Safety (enforce in code, not only in prompts)
- Never force-push, never `git add -A/./-u`, never `reset --hard`/`clean`/`stash`/checkout in the project checkout, never `--admin`, never delete a branch except by `gh pr merge --delete-branch` on its own merged PR.
- Refuse to run a worktree operation if the target path is not under `$BELT_HOME`.
- Never merge a risky PR. Never merge unless the review names the PR's current full head SHA.
- A reviewer that changes its worktree (HEAD or `git status`) fails the review; unreadable state fails it too.
- No ticket is claimed while `WORKER_CMD` or `REVIEWER_CMD` is unset.
- All `gh` writes target the repo slug explicitly (`-R`).
- Every slot and check runs through `guard_exec`: no key and no env var opts a slot out, and the sandbox denies
  writes to the real home, `/Volumes`, `belt.conf` and `TOOLS_DIR`. `CHECKS_UNSANDBOXED=1` is the one exception and only for
  checks; an Xcode project must set it, and `belt backup` is then the safety net.
- `belt backup` never passes `--delete`; a missing `TOOLS_DIR` stops pruning and pings the owner.
- Logs never contain tokens; do not print env.

## worker-rules.md (generic; write it, <= 30 lines)
Unattended engineer; nobody answers questions; decide sensibly, write doubts in the receipt. Read AGENTS.md/CLAUDE.md first. Simplest code that works.
Fresh worktree on its own branch: do NOT run git add/commit/push/reset/rebase/stash/clean/checkout, nor any write via `gh`. Leave changes uncommitted; belt commits.
Touch only files inside this worktree and OUT_DIR; never edit CI config, belt.conf, or secrets. Test files are always yours to edit, add to or delete from. Never skip/loosen/delete a test to pass a check. Add tests for behaviour changes.
Run the project's own checks if you can find them. Never claim a check passed unless you saw it pass; say NOT RUN and why.
In a project with an `.xcodeproj`, or a `Package.swift` that uses macros, do NOT run `xcodebuild` or `swift build` yourself: Apple's tools start their own sandbox and fail inside the slot sandbox. Belt commits and its checks build right after you; a build error from them comes back in the next round.
Outputs into OUT_DIR: `commit.txt` (first line < 72 chars), `title.txt` (PR title), `receipt.md` (<= one screen: files changed, each acceptance criterion with evidence, open doubts),
`owner-steps.txt` (optional, plain one-line human-only steps), or only `nochange.txt` with the reason if it needs an owner decision / is already done / cannot be done safely.

## Done when
`bash tests/selftest.sh` passes, `shellcheck`-style sanity (`bash -n` on every script) passes, `belt help` works, and every station above exists in code.
Write a short `README.md` (<= 25 lines) for the belt folder itself. Do not run `belt run` against any real repo.

## SPEC changes: batches (planned, not yet built)
Planned, not yet built: this section is the remaining batching contract. The full suite, timing stamps, budgets, watch,
thresholds and owner pings above are built; `BATCH` is not read by `belt` yet.

### New config key (optional, same file and syntax as the rest)
- `BATCH` (default `1` = no batching, today's behaviour: every PR runs remote CI on its own): a ceiling on how many
  PRs one batch may carry, never a target. A positive value enables batching (see "Batch sizing"); `batch-ci`
  budgets apply per batch run.

### Stations: what changes
3 (implement). The "files that may change" list never excludes tests: a worker may always edit, add or delete test
files, and `worker-rules.md` says so. Never skip, loosen or delete a test to make a check pass.
4 (checks). `CHECK_BUILD`, `CHECK_TEST`, `CHECK_LINT` are the fast per-ticket checks: unit tests, type-check, the
tests mapped to the touched files, and one small fixed smoke set for the riskiest flow. The full suite never runs
per ticket. Order is always local checks (station 4) -> review (7) -> remote CI (8).
7 (review). Only `P1:` lines and unmet acceptance criteria start a fix round; `P2:`/`P3:` lines are posted on the PR
and in the receipt and never block a merge, for risky and routine diffs alike.
8 (merge gate) / 10 (failure). A failed remote run is re-run only on an infrastructure failure (sharded job exit 75,
runner lost or cancelled, `timed_out`, a failed log with no test-failure line). A real test failure goes to the fix
round with its log. Never a blind re-run, never a second blind re-run.

### Batch sizing (a judgement, per project and per moment, never a fixed number)
Batch what is ready when nothing else is about to finish. Keep batches small, 1-3, when changes overlap, touch shared
or risky code, early in a new project, or during a big version update where many changes interact. Go larger, up to
~8-10, only for independent, localized changes. A release of hundreds of changes is batched by area or milestone so
every batch stays traceable. `BATCH` is the ceiling; the size inside it is chosen each round and logged with the why.
A red batch is bisected: split the batch in halves, run CI on each half, recurse until the culprit is isolated. Never
guess which PR broke it, and never re-run the batch hoping it passes (infrastructure failures excepted: one re-run).

## SPEC changes: pipeline switch, waiters, CI evidence, tolerant parsing (planned, not yet built)
Planned, not yet built: the contract for the next build round. No belt code and no new `belt.conf` keys yet.

### Switching pipelines (before any switch)
Workers run from temp copies (`<pipeline>.XXXX`), so find them by process tree, never by name or `grep run.sh`.
1. List every worker: each lock holder's pid plus its children (`ps -axo pid,ppid,command`).
2. Stop the whole tree (TERM, then KILL after a grace period) and confirm each pid is gone.
3. Cancel their CI runs (`gh run cancel`; `gh pr checks` to find them).
4. Only then switch. A worker left alive re-runs a CI run the lead just cancelled.
Planned command: `belt stop <issue>|--all` runs steps 1-3 and logs what it stopped and cancelled. `belt` itself
stays free of pipeline-specific names.

### Station 8 (merge gate): waiters and CI evidence
- A waiter exits only on a finished state: completed success, failure or cancelled. Never on queued, pending or
  in_progress; it keeps polling to CHECK_WAIT_MIN and its last line names the state it saw.
- On any failure the step prints the failing log's tail into the job output (runners wipe the workspace) and keeps it
  in the ticket dir. A failure that repeats the same way is a bug, not infrastructure: reproduce it locally with
  logs, never re-run a third time.

### Station 7 (review): tolerant parsers, strict verdicts
- Accept harmless format variation: bold or heading-wrapped lines (`**VERDICT: PASS**`, `## Findings`), two summary
  blocks, prose before the verdict.
- Fail only when the verdict itself is missing (no `VERDICT: PASS|FIX` line). When only the format failed, the lead
  may decide the review from its findings and notes why in the ticket log.

## The Jev reflex layer (optional, planned; not built into the belt yet)
A TypeSafe System One model as a bounded classifier for routine judgments, never a planner or a writer.
- Detect in Step 1: a TypeSafe key in pi's auth store or `TYPESAFE_API_KEY`, or the pi extension `@riposta/pi-jev`.
  Offer it only when present; a project without it runs exactly as today. Never required.
- Use it only for bounded, high-volume yes/no or pick-one judgments with typed questions and the decision in code:
  worker report admits a failure or blocker, worker looping or stalled, review-finding severity (P1 vs not),
  red-batch attribution, ticket routing. LLMs stay for words, code and reasoning.
- Rollout: shadow mode first (log the verdict, never act), calibrate on the project's real receipts, logs and
  reviews, then promote one check at a time when it agrees with the lead. Thresholds come from that data, never
  guessed; start with the bands 0.7 / 0.3.
- Privacy: every call sends the prompt and diff to api.typesafe.ai. The owner approves that per project; record the
  approval in `docs/kickoff/decisions.md`.
- Planned config keys (comments only, like `BATCH`): `JEV_CHECKS` (default empty = off; space-separated
  from the list above), `JEV_MODE` (default `shadow`; `live` only after calibration), `JEV_THRESHOLDS` (`0.7/0.3`).
