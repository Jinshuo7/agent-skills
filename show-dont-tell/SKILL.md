---
name: show-dont-tell
description: Turn what we're talking about right now into images to look at. Routes the job to the image model whose strengths fit what it must hold, confirms once, generates, and drops the round into Eagle. Claude may start it without the user typing /show-dont-tell whenever the next step is generating stills (styling a blockout, a storyboard frame, a look to see); nothing is generated until the user approves the plan in step 3.
---

# Show, don't tell

The user wants to *see* the thing under discussion, fast. The source is this conversation: what was just said, described or decided. Read nothing outside it except the reference images and notes named below.

Tools: `T="/Volumes/Jinshuo Edit_A/AI Filmmaker/_studio/tools"`. Notes: `/Volumes/Jinshuo Edit_A/AI Filmmaker/_studio/notes/`.

## 1. Read the moment

Decide, from the last stretch of conversation:
- **Subject**: what the user wants to see.
- **Kind**: environment or landscape, character, prop, layout or graphic, or an edit of an existing image.
- **Must-holds**: the one or two things the image fails without: a sketch's layout and scale, a face's identity, exact text, the film's style lock, a long edit chain, a transparent background.
- **Aspect ratio**: 16:9 for film frames unless the kind calls for another.
- **References**: images the user named, plus images in the folder we're working in that bear on it (the film's `style/` references and its locked style paragraph in `style/style-lock.md`, the character's picked face, a picked location). Every reference that applies goes in.

## 2. Pick model and route

Route by the must-holds. Read the "Routing" section of `image-models.md`: each model's strengths, weaknesses and the evidence behind them. Pick the model whose strengths cover the must-holds and whose weaknesses miss them. When no single model covers two must-holds, plan a **chain**: the first model makes what it holds best, the second edits only the rest (e.g. Seedream holds a blockout's layout, then GPT Image 2.6 restyles it with "change only the style"). When the evidence for the job is thin, plan a two-model test (2 takes each) instead of a guess. Then read that model's prompting file in `image-prompting/` (start at its `README.md`) and `genspark-free-limits.md` (highest free setting per model).

| Route | When | Setting |
|---|---|---|
| Genspark (default) | any model, references pasted in | the model's highest free setting |
| Codex | GPT Image 2.6 only, when the Genspark window is down or stopped | references attached |

## 3. Confirm once

This is the user's OK, and it is required even when Claude started the skill itself: never generate before the user answers it.

One `AskUserQuestion` call, two questions:
1. **Plan**: "I think you want to see <subject>. It must hold <must-holds>, so <model> (strong at <the strength that covers them>) via <route>, <ratio> <size/quality>, references: <names>." Options: the plan (Recommended), your second-choice model or chain, and a two-model test.
2. **How many**: 1, 2, 4, 8. With more than one, name the **variation axis** in the option: "4, varying <angle / light / time of day / framing / design detail>" (Recommended), or "4, same prompt".

On every later run in this session, make "Same as last time (<route>, <model>, <n>)" the first option of each question.

**Lock layout with a Blender guide** (optional): when the subject is a staged shot (people placed in a set, a set camera), add the option "Lock layout with a Blender guide" to the Plan question. If chosen, run the `block-it-out` skill first (steps 1-4: spec, render, check, the user's OK on the layout), then come back here. Every character and key prop in the sketch has a colour and a reference (block-it-out step 0; the user confirmed the list). The layout is a must-hold, so route it by step 2 (in the 2026-11-20 tests only Seedream 5.5 held a sketch's scale). Refs in every job: `blockout/<shot>/guide.png` as image 1, framed as an edit of it ("Edit Image 1. Keep the composition unchanged. Remove all sketch colours."), the style reference as image 2 (run with `--no-auto-refs`), then one reference per colour, with each image's number and role named in the prompt (column 8 of the Genspark jobs.tsv, or extra arguments to `gen-image.sh`). The prompt carries block-it-out step 5 (Photo)'s content: legend, sizes, the Blocking line, the scene line (the same in every shot of a batch), then the story moment. Shape and order follow the chosen model's prompting file; Seedream also gets a `<bbox>` per colour, measured from `guide.png`. Describe light by the lamps the set actually has: loose light shapes with no source turn into objects. When checking the result: with three or more people, first check the left-to-right order and who holds what against the sketch, and re-roll a frame that misses (the frame-order line holds about 6 frames in 7, so a re-roll usually lands). Then measure the zoom (styled figure height ÷ sketch figure height). Above 1.15x, offer the zoom-out repair (`_studio/tools/zoom-out.sh`, method in `_studio/notes/blockout-to-image.md` r5-r6); in the 2026-11-18 self-test, frames of one or two people came in at 0.9-1.2x and crowds of five at 1.3-1.6x.

**Agreement gate.** Before a Blender-guided run, send `guide.png` and the prompt's action lines to the visual-checker. It writes what the sketch shows first (who faces where, where each gun and sword points, each pose), then compares that with the prompt line by line. A mismatch stops the run. Make the sketch and the prompt say the same thing (fix the blockout with block-it-out, or the prompt), then check again.

## 4. Write the prompts

Folder `show/<YYYY-MM-DD>/` in the film folder (or the current folder). Name the round with a short slug. One prompt file per image: `<slug>-NN.prompt.txt`. First line `Design: <what this image varies>`, then the full prompt. When the folder has a style lock, its style paragraph goes in word for word. For "same prompt" rounds on Genspark, write one prompt file `<slug>.prompt.txt` and use the count column instead.

## 5. Generate (in the background, wait for the notification)

- **Genspark**: `jobs.tsv`, one line per prompt, tab-separated: `prompt-file  output.png  model  ratio  size  quality  count  refs` (model and ratio required; leave size and quality blank to get the model's highest free setting; refs comma-separated; the film's `style/auto-refs.txt` images are added first automatically, so don't list them). Run from the film folder: `"$T/genspark-batch.py" show/<date>/<slug>-jobs.tsv --quiet-hours none` (add `--no-auto-refs` when you list the style reference yourself, and `--timeout 900` for GPT Image 2.6 at 4K with several references). The user is present, so quiet hours are off. After each image is saved, the script deletes that job's Genspark chat so rounds don't fill the user's task list; never add `--keep-chats` unless the user asks.
- **Codex**: `"$T/gen-image.sh" <prompt-file> <output.png> <ref> ...` per image, all started with `&`, then `wait`.

If the Genspark script prints STOPPED, tell the user its reason in one line. A credit pop-up means the setting isn't free: rerun at a free setting. Never continue with credits.

## 6. Show

Show the pictures, not a description. Build one comparison sheet `show/<date>/<slug>-compare.jpg` with `magick` (`-font /System/Library/Fonts/Supplemental/Arial.ttf` for captions): the top row holds every reference used, each captioned with its image number and role (Blender sketch, style, each character or prop); below it go the results, each captioned with its model or variant (and its size against the sketch in Blender-guided rounds). Send it with `SendUserFile`, `display: render`, as the last thing in the reply. While the round runs, tell the user in one line what is generating.
- **In a film folder** (has `status.md` and a `*.library`): also `"$T/eagle.py" add "Show, don't tell/<date> <slug>" show/<date>/<slug>*.png show/<date>/<slug>-compare.jpg`, and name the Eagle folder.

The user is the judge here: skip the worker check and don't open the images yourself. **Exception, Blender-guided rounds:** before the Eagle step, send the images, `guide.png` and the reference sheets to the **visual-checker** subagent with three claims per image: scale (figures the same size in frame as in the sketch, horizon at the same height), identity (each colour became its reference character), and props (each coloured prop has its reference's look and colour). Report its verdict in one line per image along with the Eagle folder. End with one line: images this round, images this session.

## 7. After the pick

- "Put #N in <place>": copy the image and its prompt file into that folder of the film (characters, locations, frames ...) and say where it went.
- "More like #N": run again from step 3 with #N added as a reference.
