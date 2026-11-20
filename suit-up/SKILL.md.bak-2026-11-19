---
name: suit-up
description: Equip one project with skills from the user's skill library - a manager kit linked into the project, a worker kit, and a phase-to-skill plan - so other projects stay unaffected. Use only when (a) the user says "suit up" or "suit down"; (b) the project's .suit-up/kit.md says "status: active" and the phase changes or the kit needs editing; or (c) as a one-time offer at the first substantial work in a project the user will return to that has no .suit-up/ folder (in a git worktree, look in the main checkout). Never offer when .suit-up/kit.md says "status: declined". Not for installing new skills, editing skill contents, or changing global skills.
---

# Suit Up

## The model
- Library: one or more folders that hold all the user's skills
  (`<library>/<skill>/SKILL.md`). Harnesses don't load it directly.
- Global skills: the few skills a harness loads everywhere. Suit-up
  never changes them.
- Project kit (manager): symlinks in `<project>/.claude/skills`, each
  pointing at a library skill. Only sessions in this project see
  them.
- Worker kit: a list of skill folder paths in
  `.suit-up/worker-kit.txt`, given to workers at launch. Workers may
  start outside the project, so never rely on project folders for
  them.
- Per phase: nothing is linked. Skills are handed over by absolute
  path.

Goal: every session and every worker sees only what it might use.

## Terms
- Helper: `H="python3 <this skill's folder>/scripts/suitup.py"`. It
  uses only the Python standard library. All listing, linking and
  unlinking goes through it.
- Project `P`: the folder the user names; otherwise, in a git repo,
  the main checkout of the current folder:
  `P=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")`
  P is never a worktree path. Outside git, P is the current folder.
- Records: `P/.suit-up/`. A session in a worktree reads and writes
  the main checkout's records. Never commit `.suit-up/`.
- Kit link: a symlink in `P/.claude/skills` that points into the
  library. Anything else in that folder is foreign.
- Paths may contain spaces. Quote "$P" in every command. If P
  doesn't exist, stop and tell the user.
- For a manager harness other than Claude Code, pass its project
  skills folder with `--dir` (for example `--dir .pi/skills`).

## Hard rules
- Create and remove kit links only with the helper. Run every
  `link` and `unlink` as a dry run first, read the output, then
  repeat with `--apply`.
- Never touch foreign entries. If the helper reports a clash, stop
  and ask the user.
- Never edit, move or delete anything inside the library or a
  global skills folder.
- Never link anything before the user approves the proposal.
- Suit-up doesn't install skills. If a need has no library skill,
  say so in the proposal.

## First use on a machine
Run `$H where`. If it reports no library, ask the user which folder
holds their skills (the helper lists folders that look like one),
then run `$H set-library "<folder>"`. Several folders are allowed.

## The offer (trigger c)
Ask once: "Want me to suit up this project?" If the user declines,
write `P/.suit-up/kit.md` with `status: declined` and the date (in a
git repo, also add `.suit-up/` to `P/.gitignore`), and don't offer
again in this project unless asked.

## Mode 1: Suit up a project
1. Understand the project: README, file tree, AGENTS.md/CLAUDE.md,
   and what the user says the work is. If there's no README, ask the
   user what the work is. Identify likely phases (code, e.g.
   research, planning, backend, frontend, review; non-code, e.g.
   research, logging, scripting, editing, delivery).
2. Scan the library once: `$H list` prints one line per skill
   (name | path | description cut to 200 characters). "(manual)"
   after a name marks a manual-only skill
   (`disable-model-invocation: true`). Open a SKILL.md only to break
   a tie.
3. Draft three lists:
   - Manager kit (aim 3–10): what the manager itself uses throughout
     this project: planning, review, delegation, and work it does
     directly.
   - Worker kit (aim 2–8): what every worker in this project needs.
     Skip it if the user has no workers.
   - Phase plan: for each phase, 1–3 extra skills, each tagged for
     manager or worker.
   Rules: include a skill only if you can name a concrete task here
   it serves; prefer one broad skill over overlapping ones; skip
   anything the harness already loads globally (Claude Code:
   `~/.claude/skills`).
4. Propose, then wait for approval or edits: one table per list
   (skill | reason), notable skills left out and why, and needs that
   no library skill covers. Write "(manual)" after every manual-only
   skill: a worker's catalog doesn't show it, so briefs must name
   it. Do only what is approved. If everything is rejected, treat it
   as a decline (see "The offer").
5. Pre-link checks (only if the approved manager kit has at least
   one skill):
   - Git: `git -C "$P" rev-parse --is-inside-work-tree` prints
     "true" → git: yes. Anything else → git: no; skip the next
     check and the .gitignore step.
   - Git: yes and `git -C "$P" ls-files .claude/skills` prints
     anything: stop and ask the user (the folder holds committed
     skills; ignoring it would hide them).
   - `$H status "$P"`: note foreign entries and leave them alone.
6. Link the kit: `$H link "$P" <skill>...` (dry run), then the same
   with `--apply`. Git: yes: add `.claude/skills/` and `.suit-up/`
   to `P/.gitignore` if they aren't there. Confirm with
   `$H status "$P"`.
7. Write the records (format below): .suit-up/kit.md,
   .suit-up/worker-kit.txt, .suit-up/plan.md.
8. Activation: newly linked skills may appear in this session
   automatically; if not, run /reload-skills, or open a new window.

## Mode 2: Change phase or update the plan
Only when kit.md says "status: active".
1. Check the records and report any problem before continuing:
   - paths in plan.md and worker-kit.txt whose folder no longer has
     a SKILL.md;
   - `$H status "$P"`: `kit-broken` links, and any difference
     between the kit links and the skills in kit.md.
2. Read .suit-up/plan.md. For the new phase, use its skills by path
   (read them yourself, or hand them to workers).
3. Change the manager kit only if a skill will be needed across many
   future sessions: propose → approve → `link` or `unlink`, then
   update kit.md.
4. Update plan.md when phases or skills change.

## Mode 3: Brief a worker
If the user has their own worker-briefing guide, follow it.
Otherwise read references/workers.md.

## Mode 4: Suit down
1. `$H unlink "$P" --all` (dry run), then with `--apply`. It removes
   kit links only; foreign entries stay.
2. Keep the records and set kit.md to "status: inactive".
Worker kits need no undo.

## Record formats
.suit-up/kit.md (one field per line)

    # Project kit: <project>
    status: active | inactive | declined
    updated: <YYYY-MM-DD>
    git: yes | no
    - <skill>: <reason>

  A declined record has only the title, status and updated lines.

.suit-up/worker-kit.txt

    one absolute skill folder path per line; "# <skill>: <reason>" comments allowed

.suit-up/plan.md

    # Phase plan: <project>
    ## <phase>
    - <skill> (manager|worker): <absolute path> | <reason>
    ## Left out on purpose
    - <skill>: <reason>
