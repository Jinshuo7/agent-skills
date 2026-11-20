---
name: genspark-image
description: Make images on Genspark's free image page (genspark.ai/ai_image) by driving a logged-in Chrome window with a script. Use whenever the user wants an image, a quick look at an idea, a concept still, a reference picture, or a batch of images, and no other image route is named. No AI tokens are spent on generation. macOS only.
---

# Genspark image generation

`scripts/genspark-batch.py` fills in Genspark's image page like a person would and saves the results. It uses no model; you write the prompts and the job list, then run the script.

## 1. Check the Chrome window

The script works only through a dedicated Chrome window with a debug port. Check it:

```bash
curl -sf http://127.0.0.1:9333/json/version >/dev/null && echo running || echo "not running"
```

If not running, start it (`python3 <skill>/scripts/genspark-batch.py --help-chrome` prints the same command):

```bash
open -na "Google Chrome" --args --user-data-dir="$HOME/.agent-browser-profiles/genspark-chrome" --remote-debugging-port=9333 --no-first-run --disable-backgrounding-occluded-windows --disable-renderer-backgrounding --disable-background-timer-throttling https://www.genspark.ai/ai_image
```

First time only: the user logs in to Genspark in that window by hand (Google sign-in blocks automation). Wait for them to confirm. The login is kept in that profile.

## 2. Write the jobs file

A TSV file, one job per line, columns separated by real tabs:

```
<prompt text or prompt file>  <output path>  <model>  <ratio>  [size]  [quality]  [count]  [refs]
```

- **model** (required): a name from Genspark's model menu, e.g. `Nano Banana Pro`, `GPT Image 2.6`, `Seedream 5.5`. Genspark remembers the last choice, so every job must name one.
- **ratio** (required): `21:9 2:1 16:9 3:2 4:3 1:1 3:4 2:3 9:16 1:2 9:21` or `Auto Size`.
- **size, quality**: leave blank. The script fills in the model's highest free setting from `scripts/genspark-free-limits.json` and refuses any setting that costs credits.
- **count**: `1`, `2` or `4` images from one request (blank = 1). With 2 or 4, files are saved as `name-1.png`, `name-2.png` and so on.
- **refs**: reference images, comma-separated paths.
- Lines starting with `#` are skipped. Jobs whose output already exists are skipped.

For long prompts, write each one to a `.txt` file and put its path in column 1.

After a job's images are saved, the script deletes that job's chat from Genspark's task list (found by its chat id; pinned chats are never touched; a failed delete only prints a note). `--keep-chats` keeps them. A job that stops after Send (timeout, limit, failed download, lost browser connection) also gets its chat id written to `genspark-log.jsonl` as a "stopped" line and its chat deleted; after a human-verification check the chat is only logged. Old chats named in `genspark-log.jsonl` files: `scripts/genspark-delete-chats.py <folder>`.

Optional: a project can have `style/auto-refs.txt` (one image path per line). Those images are added first to every job run from that folder. `--no-auto-refs` turns that off for one run.

## 3. Run it

From the project folder:

```bash
python3 <skill>/scripts/genspark-batch.py jobs.tsv --check   # shows final settings, no browser
python3 <skill>/scripts/genspark-batch.py jobs.tsv
```

- Each run opens its own tab, so several runs can go at once, each on a share of the jobs. Each run is about 10-30 s per image.
- Run long batches in the background.
- Pacing defaults: 1-7 s gaps, `--per-hour 25`, `--quiet-hours 1-7` (no runs 1-7 am). Raise `--per-hour` only if the user asks.
- A log `genspark-log.jsonl` is written next to the outputs.

## 4. When it stops

The script stops with a screenshot on a limit message, a credit prompt, a human-verification check, a page layout change or a timeout. Tell the user what the stop line says.

- **Limit**: Genspark's image limit is a rolling 5-hour count. The stop line shows the reset time (`RESETS: ...`). Tell the user and wait; more tabs don't raise it.
- **Verification check**: the user solves it by hand in the Chrome window.
- **Layout change**: Genspark changed its page; the script's selectors need updating.

## Rules

- Never click "Continue with Credits" or tick "don't ask again". The script refuses paid settings; don't work around that.
- Auto Prompt is turned off by the script so Genspark doesn't rewrite the prompt. Leave it off unless the user asks (`--auto-prompt`).
- Show the user the saved images; don't describe them as done until the files exist.
- Free limits per model are in `free-limits.md`.
