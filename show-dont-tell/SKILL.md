---
name: show-dont-tell
description: Turn what we're talking about right now into images to look at. Picks Genspark or Codex and the model, confirms once, generates, and drops the round into Eagle.
disable-model-invocation: true
---

# Show, don't tell

The user wants to *see* the thing under discussion, fast. The source is this conversation: what was just said, described or decided. Read nothing outside it except the reference images and notes named below.

Tools: `T="/Volumes/Jinshuo Edit_A/AI Filmmaker/_studio/tools"`. Notes: `/Volumes/Jinshuo Edit_A/AI Filmmaker/_studio/notes/`.

## 1. Read the moment

Decide, from the last stretch of conversation:
- **Subject**: what the user wants to see.
- **Kind**: environment or landscape, character, prop, layout or graphic, or an edit of an existing image.
- **Aspect ratio**: 16:9 for film frames unless the kind calls for another.
- **References**: images the user named, plus images in the folder we're working in that bear on it (the film's `style/` references and its locked style paragraph in `style/style-lock.md`, the character's picked face, a picked location). Every reference that applies goes in.

## 2. Pick model and route

Read `image-models.md` (which model for which kind) and `genspark-free-limits.md` (highest free setting per model). Choose the model that fits the kind.

| Route | When | Setting |
|---|---|---|
| Genspark (default) | any model, references pasted in | the model's highest free setting |
| Codex | GPT Image 2.6 when the Genspark window is down or stopped | references attached |

## 3. Confirm once

One `AskUserQuestion` call, two questions:
1. **Plan**: "I think you want to see <subject>. <Model> via <route>, <ratio> <size/quality>, references: <names>." Options: the plan (Recommended), and your second-choice model.
2. **How many**: 1, 2, 4, 8. With more than one, name the **variation axis** in the option: "4, varying <angle / light / time of day / framing / design detail>" (Recommended), or "4, same prompt".

On every later run in this session, make "Same as last time (<route>, <model>, <n>)" the first option of each question.

## 4. Write the prompts

Folder `show/<YYYY-MM-DD>/` in the film folder (or the current folder). Name the round with a short slug. One prompt file per image: `<slug>-NN.prompt.txt`. First line `Design: <what this image varies>`, then the full prompt. When the folder has a style lock, its style paragraph goes in word for word. For "same prompt" rounds on Genspark, write one prompt file `<slug>.prompt.txt` and use the count column instead.

## 5. Generate (in the background, wait for the notification)

- **Genspark**: `jobs.tsv`, one line per prompt, tab-separated: `prompt-file  output.png  model  ratio  size  quality  count  refs` (model and ratio required; leave size and quality blank to get the model's highest free setting; refs comma-separated; the film's `style/auto-refs.txt` images are added first automatically, so don't list them). Run from the film folder: `"$T/genspark-batch.py" show/<date>/<slug>-jobs.tsv --quiet-hours none`. The user is present, so quiet hours are off.
- **Codex**: `"$T/gen-image.sh" <prompt-file> <output.png> <ref> ...` per image, all started with `&`, then `wait`.

If the Genspark script prints STOPPED, tell the user its reason in one line. A credit pop-up means the setting isn't free: rerun at a free setting. Never continue with credits.

## 6. Show

- **In a film folder** (has `status.md` and a `*.library`): `"$T/eagle.py" add "Show, don't tell/<date> <slug>" show/<date>/<slug>*.png`, then tell the user the Eagle folder name.
- **Elsewhere**: `"$T/contact-sheet.sh" show/<date> show/<date>/<slug>-sheet.jpg`, then `SendUserFile` with `display: render`.

The user is the judge here: skip the worker check and don't open the images yourself. End with one line: images this round, images this session.

## 7. After the pick

- "Put #N in <place>": copy the image and its prompt file into that folder of the film (characters, locations, frames ...) and say where it went.
- "More like #N": run again from step 3 with #N added as a reference.
