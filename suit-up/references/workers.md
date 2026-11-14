# Giving the kit to workers

Read this when briefing a worker and the user has no worker-briefing guide of their own.

A worker is any cheaper agent the manager launches for bulk work. It usually starts outside the project folder, so it gets its skills at launch, not from the project.

## What to pass
- Every path in `P/.suit-up/worker-kit.txt`. Skip blank lines and lines starting with `#`.
- The current phase's worker skills from `P/.suit-up/plan.md`.
- Before launching, drop any path whose folder no longer has a `SKILL.md`, and tell the user which ones you dropped.

## How to pass it
Use whichever the worker harness supports:

1. **A skill flag at launch.** Pi takes one `--skill <skill folder>` per skill (the folder, not the SKILL.md file). In zsh or bash:

   ```bash
   KIT=(); while IFS= read -r s; do [[ -n $s && $s != \#* ]] && KIT+=(--skill "$s"); done < "$P/.suit-up/worker-kit.txt"
   pi -p "${KIT[@]}" "<brief>"
   ```

   With Pi, a worker given skills needs at least the read tool; with no tools it sees no skills. A skill that runs scripts also needs a shell tool.

2. **A line in the brief.** This works with any harness that can read files:

   ```
   Skill: read <absolute path>/SKILL.md first and resolve its relative paths from that folder.
   ```

## Manual-only skills
A skill marked "(manual)" (`disable-model-invocation: true`) doesn't appear in a worker's skill catalog even when passed with a flag. The brief must name it: `/skill:<name>` where the harness supports it, or the "Skill: read …" line above.

## In the brief
Give the task, only the context this task needs, and point at the one or two skills that matter most. The worker doesn't need the project's structure.
