# Genspark image skill: setup

Makes images on Genspark's free image page by driving Chrome. Works with Codex, Claude Code, Pi, or any agent that reads skills. macOS only.

## Needs
- macOS with Google Chrome and Python 3 (no extra packages)
- A Genspark account

## Install
1. Put this whole folder where your agent reads skills:
   - Codex: `~/.codex/skills/genspark-image/`
   - Claude Code: `~/.claude/skills/genspark-image/`
   - Or add it through Skills Manager if you use it.
2. Start Chrome with the command in `SKILL.md` step 1 and log in to Genspark once by hand in that window.
3. Ask your agent for an image. It reads `SKILL.md` and runs the script.

## Notes
- Genspark changes its page sometimes. If the script stops with a layout error, the selectors in `scripts/genspark-batch.py` need updating.
- `free-limits.md` lists each model's highest free size and quality as of November 2026.
- Genspark's terms on automated use haven't been checked. Keep the default pacing.
