# suit-up (universal)

Per-project skill kits without any skill-manager app. Skills stay in one library folder; suit-up links the ones a project needs into that project, so other projects are unaffected.

## Requirements
- macOS or Linux, `python3`, `git` (git is optional per project).
- A folder of skills laid out as `<library>/<skill>/SKILL.md`.
- Windows is not supported: it needs symlink permission, and there is no copy mode yet.

## Install
Put this folder where your harness loads global skills (Claude Code: `~/.claude/skills/suit-up`). On first use it asks where your skill library is and saves the answer in `~/.config/suit-up/libraries` (or set `SUIT_UP_LIBRARY`).

## What it writes
- `<project>/.claude/skills/<skill>`: symlinks into the library.
- `<project>/.suit-up/`: `kit.md`, `worker-kit.txt`, `plan.md`.
- In git repos, two lines in `.gitignore`: `.claude/skills/` and `.suit-up/`.

It never changes the library or global skills folders.

## History
The earlier version drove the Skills Manager CLI and is archived as `suit-up-skills-manager`.
