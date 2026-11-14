---
name: factory-setup
description: Set up or re-tune a software project's agent team from the person's own tools, plans and preferences. Use when they start a new project, run /factory-setup, or want to change their team after a plan or model change. Scans what is installed, asks and confirms, optionally runs a short model trial, then builds the folder, repo, belt and lean instruction files and names the next step.
---

# factory-setup

Aim: about 10 minutes, mostly clicks. You are the head: delegate detailed reading, decide from short
summaries. `SKILL_DIR` = this file's folder. `BELT` = `SKILL_DIR/belt/belt`.

## Rules
- Never assume. Use only what you detected, measured or researched; ask the rest.
- Ask with your tool's question pop-up when it has one (several independent questions at once), up to
  three options; mark "(Recommended)" only when evidence backs it, never on facts about the person.
- Never add a schedule, pause, throttle or limit the person did not ask for. Prices are facts to show.
- Never overwrite a file, touch another project, install anything, or change anything global without a yes.
- Never guess a command line: research it, then prove it with `BELT slot-test`.
- Notes go in `<project>/docs/kickoff/`. Helpers write one page; read it, open the source only if needed.

## Checks, batches, time
- Checks scale with the change: fast checks per ticket (unit, type-check, the touched files' tests, one small
  smoke set for the riskiest flow), the full suite once per batch and before each release; over 15 min means
  batching and sharding are built at build time, not later.
- Order: local checks, review, remote CI. Only P1 and unmet acceptance criteria start a fix round, P2/P3 are
  posted and never block; a failed run is re-run only on an infrastructure failure, never blindly. Workers may
  always edit test files; "files that may change" never excludes tests.
- Batch size is a judgement per project and moment, never a number: what is ready when nothing else is about
  to finish; 1-3 when changes overlap, touch shared or risky code, early on or in a big version update; larger
  only for independent, localized changes; by area or milestone for a big release; a red batch is bisected.
- Never sit broken: every wait and model call has a cap (a call is hung after `SLOT_IDLE_MIN` with no output,
  file change or CPU; `SLOT_MAX_MIN` is the last-resort ceiling, never elapsed time alone). `belt watch` runs
  every 10 min for free and hands each stall (stuck, waiting lead, silent ticket, over budget, red base) to the
  cheap On-call slot to fix. Only what On-call cannot fix reaches the owner, once, via `OWNER_NOTIFY_CMD`.
  A Claude head session is never the watcher. Every slot and every check is guarded: throwaway `HOME`, a sandbox
  that allows writes only to its own work folder and caches, and never `belt.conf` or `TOOLS_DIR`; there is no
  opt-out key. `belt backup` snapshots the config and the owner's tools with hardlinks, never `--delete`.
- Tests never touch real tools: every test and fixture runs with a throwaway `HOME`, and examples name real paths only as placeholders.
- Time budgets come from measured stage times (the trial or the first tickets), never guesses.

## Mode
- **Re-tune** (`belt.conf` exists): Steps 1-4 for the team only (add an On-call slot and the watch agent
  when missing), then 6.2; update the team lines in
  the instruction files; commit; stop.
- **Existing project** (a git repo with code or agent docs, no `belt.conf`): keep every existing file
  and command; skip Step 5.1 and repo creation when a remote exists. Step 1 also lists the remote, default
  branch, current branch, open PRs, instruction files, skills, earlier notes and build/test commands, and
  times the full suite. Ask only what those don't answer; the approval screen lists only what will be
  added; existing build/test commands go into `belt.conf`; the next steps go into the existing handoff. On
  an unmerged setup branch, let the person choose where to commit. If the project already has a working
  merge pipeline, say so and recommend not adding the belt.
- **New**: every step.

## Step 1: Scan (silent)
- `git`, `gh` (and `gh auth status`), `jq` (the belt needs it), `python3` (the trial needs it).
- Every coding-agent CLI on the machine (e.g. `claude codex pi opencode aider gemini cursor-agent`): signed
  in or not, and its model list. Skill packs installed (skills manager, `~/.claude/skills`, `.claude/skills`, plugins).
- Reflex layer: a TypeSafe key in pi's auth store or `TYPESAFE_API_KEY`, or the pi extension `@riposta/pi-jev`. Offer
  it only when found, never required; it sends prompts and diffs to api.typesafe.ai, so the owner approves per project.
- Measure: run the full test suite once and time it (wall clock, minutes); record it in `brief.md`.
Missing tools: offer to install. Signed-out tools: the person signs in; never type credentials.

## Step 2: Ask, then confirm
1. The app in one sentence (free text).
2. Platform: web / iPhone / Android / Mac / other.
3. Stakes: just me / real users / money or private data.
4. About you: how technical, and how involved (taste questions only / weekly check-ins / every decision).
5. Plans: "I found <tools and sign-ins>. Which plans, subscriptions or API keys do you have?"
6. Models: name the ones you want / no preference, run a short trial / no preference, you pick.
7. Extra monthly spend you allow, if any (free text, any currency).
8. Skill packs: "I found <packs or none>. Which should this project use?" If none, say what will be missing
   and offer to look for one.
9. Check whether something like this already exists? yes / no.
Confirm in one line ("So you have X, want Y, ... Right?") and save to `brief.md` (≤12 lines).

## Step 3: Research and trial (in parallel, background)
- Existing apps, on a yes: `templates/scout-prompts.md` (a). Limits for every candidate route: what the plan
  covers (per-model allowance, free models), rate limits and usage caps from the provider's own pages; unknown
  stays unknown. Mechanics for known tools: `SKILL_DIR/plug-in-notes.md`; research the rest.
- Read `SKILL_DIR/model-routing-lessons.md` when filling the Worker slot or writing worker briefs. Its numbers
  come from one project; treat them as evidence, not a rule.
- Trial, on "run a short trial": 2-4 candidates per role from what the plan covers. For each run
  `python3 SKILL_DIR/templates/trial/trial.py worker '<slot line>' <label>` and `... review <...>`; drop
  any `REJECTED`, score against `templates/trial/review/answer-key.md`, and write `docs/kickoff/trial.md`.

## Step 4: One approval screen
Show one table, then ask: looks good / change something / don't build.
- Team: Head (you), Worker, Routine reviewer, Risky reviewer, On-call (fixes stalls; the cheapest model the plan
  covers that passes slot-test), Gate (the belt; never a model), and how the owner is pinged (default: Mac notification). Use stated
  preferences first, then trial results. Where evidence supports it, suggest models the plan covers and a
  reviewer from a different company than the worker. Show each slot's limits and name the scarcest one; if it
  will slow the work, ask how to handle it.
- Checks: the fast per-ticket set, the measured full-suite time from Step 1, and whether it needs batches.
- Backup: `BACKUP_DIR` (ideally a second volume) and `TOOLS_DIR` (the folders holding the person's own tools); both
  are snapshotted and `TOOLS_DIR` is write-denied to every slot, so list every folder the team must not touch.
- Risky areas from the stakes. If involvement is "every decision", every merge waits for the head.
- The Jev reflex layer, only if detected in Step 1: optional, shadow mode first, one check at a time; see `belt/SPEC.md`.
- Skill pack, folder, repo name, and the existing-apps verdict if it is back.
On "change something", ask only about that line. On "don't build", note why in `decisions.md` and stop; a
later model or route needs a yes. `decisions.md` (≤20 lines) holds every slot line.

## Step 5: Build
1. New folder (empty only), `git init`, notes into `docs/kickoff/`.
2. `gh repo create <owner>/<name> --private --source .`, then `BELT install <project>` and
   `gh label create needs-owner --color D93F0B --description "A step only the owner can do"`.
3. `belt.conf`: the slot lines (worker, reviewers, `ONCALL_CMD`), the base branch (detected), the fast check
   commands (else empty), `FULL_SUITE_CMD` (the measured full suite; it runs per batch, never per PR),
   `RISKY_PATHS` (`*` when every merge must wait), `BACKUP_DIR` and `TOOLS_DIR` (from the approved screen),
   `OWNER_NOTIFY_CMD` if not the default. For an iPhone or Mac project, instead set `CHECKS_UNSANDBOXED="1"`
   and export `DEVELOPER_DIR`: Apple's build tools cannot run inside the check sandbox. Every other key stays
   at its default unless asked.
4. `BELT install --watch <project>` (the owner already approved the team screen, which lists it): the
   watcher runs through the `Belt Watch` app every 10 minutes; allow the macOS permission prompt. Install
   kickstarts the first pass and must print `PASS: first automatic run read its config`; on `FAIL`, read
   `watch.err` and fix it before going on.

## Step 6: Test and write
1. Copy the chosen pack's skills into the project only, never globally; never combine packs with the same name.
2. `BELT slot-test <project>`: every slot must PASS, On-call included. On FAIL read its 3 lines, fix the line
   or offer the next candidate, retest. Then `BELT backup <project>` (one snapshot exists under `BACKUP_DIR`) and
   `BELT drill <project>`: it fakes a stall and must show On-call fixing it and one owner ping. No PASS, no build.
3. Copy `SKILL_DIR/templates/` into `<notes>/templates/` (workers only read inside the project), fill
   `setup-brief.md`, and run the worker slot with "Read <notes>/setup-brief.md and do it". It writes the
   head card into the file the head tool loads (Claude Code: `CLAUDE.md`; most others: `AGENTS.md`), the
   worker handbook `AGENTS.md`, and `docs/agents/` OWNER-INSTRUCTIONS, NEXT-SESSION-HANDOFF, OWNER-SUMMARY
   (`<<BELT>>` = the absolute path of `BELT`). Check: head card ≤15 lines, no `<<` left; else re-run it.
4. If the chosen pack has a repo-setup skill, follow it with the answers already given.
5. Commit and push the base branch; confirm with `git status -sb`.

## Step 7: Next step
End with ≤8 lines: what was built, the team in one line, anything still running, and the next steps from
the chosen pack's real commands, into the handoff's "Next" too. Then build with the belt in a fresh lead.
