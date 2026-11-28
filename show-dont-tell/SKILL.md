---
name: show-dont-tell
description: Turn what we're talking about right now into images to look at. Picks the right image model and prompting approach for what the image must hold, confirms once, generates and reports the round; saves to the project's chosen folder and into Eagle only on request. May start without /show-dont-tell whenever the next step is generating stills (a look to see, a storyboard frame, an edit of a reference); nothing is generated until the user approves the plan in step 3.
---

# Show, don't tell

The user wants to *see* the thing under discussion, fast. The source is this conversation: what was just said, described or decided, plus the reference images it names. `<skill>` below is this skill's folder.

## Roles and config

Two roles share the work:
- **Lead**: reads the moment, routes, confirms with the user, writes the prompts, shows the result (steps 1-4, 6-7).
- **Worker**: the busy work. It runs the image script, builds the compare sheet and imports into Eagle when asked (step 5, the mechanical part of 6). Worker steps always go to the worker: brief it with `<skill>/references/worker-brief.md` and run it with the user config's `worker.call`. If the worker can't be started, stop and tell the user.

Two config files, read at the start of every run:
- **User config** `~/.config/show-dont-tell/config.json`: who fills each role and the image route/script. Missing: copy `<skill>/references/config.example.json` there and ask the user for the names before the first image.
- **Project config** `show-dont-tell.json` in the folder we work in: where this project's images are saved, its optional Eagle library and folder, and its optional style files. Missing: run **project setup** below before the first image. Template: `<skill>/references/project.example.json`.

### Project setup (once per project)

One question call:
1. **Save images to**: "`show/<date>/` in this folder" (Recommended), or another folder the user names (an absolute path is fine, also outside this project).
2. **Eagle**: "No Eagle" (Recommended), "<the library open in Eagle now>, folder `Show, don't tell/<date> <slug>`", or another library and folder the user names.
3. Only when this folder has style files (a style paragraph such as `style/style-lock.md`, a list of style images such as `style/auto-refs.txt`): "Use them in every image" (Recommended) or "No".

Write the answers into `show-dont-tell.json` and say where it is; the user can edit it any time.

## 1. Read the moment

Decide, from the last stretch of conversation:
- **Subject**: what the user wants to see.
- **Kind**: environment, character, prop, layout or graphic, an edit of an existing image, or a clean-up.
- **Must-holds**: the one or two things the image fails without: a reference's layout and scale, a face's identity, exact text, a style reference, a long edit chain, a transparent background.
- **Aspect ratio**: 16:9 for film frames unless the kind calls for another.
- **References**: every image the user named or that bears on it in the folder we're working in (a picked face, a picked location, a style image, and the project config's style images). Each reference gets a number and a role.

## 2. Pick model and route

Read `<skill>/references/model-routing.md` and the prompting guide in `<skill>/references/image-prompting/` (start at `README.md`).

| Route | When | Setting |
|---|---|---|
| Default (`config.image.route`, Codex) | still images and reference edits | `<skill>/scripts/gen-image.sh` with references attached (GPT Image 2.6 via ChatGPT app's Codex CLI; respects ChatGPT plan usage limits) |
| Alternative route (if configured in `config.json`) | when another model/provider is needed for a specific must-hold | per `config.json` |

## 3. Confirm once

This is the user's OK, required even when the lead started the skill itself: never generate before the user answers it.

One question call, two questions:
1. **Plan**: "I think you want to see <subject>. It must hold <must-holds>, so <model> via <route>, <ratio>, references: <names>." Options: the plan (Recommended), or an alternative approach/model if configured.
2. **How many**: 1, 2, 4, 8. With more than one, name the **variation axis** in the option: "4, varying <angle / light / time of day / framing / design detail>" (Recommended), or "4, same prompt".

On every later run in this session, make "Same as last time (<route>, <model>, <n>)" the first option of each question.

## 4. Write the prompts

Folder: the project config's `save_to` (`{date}` = YYYY-MM-DD; relative paths start at the folder we work in). Name the round with a short slug. One prompt file per image: `<slug>-NN.prompt.txt`. First line `Design: <what this image varies>`, then the full prompt (opening with the project config's style paragraph word for word, when it names one), which names each reference by its number and role ("Image 1 is the layout; keep its composition. Image 2 is the style.").

## 5. Generate (worker, in the background)

- Run `<skill>/scripts/gen-image.sh <prompt-file> <output.png> [ref ...]` per image from the working folder, starting them in parallel with `&`, then `wait`.
- If the project config names style images (`style.images`), pass them in the numbered reference order.
- If a command fails or hits a usage limit, stop and report the error word for word.

## 6. Show and report

Show the pictures, not a description. While the round runs, tell the user in one line what is generating.

The worker builds one comparison sheet `<save_to>/<slug>-compare.jpg` with `magick` (`-font /System/Library/Fonts/Supplemental/Arial.ttf` for captions): the top row holds every reference used, each captioned with its number and role; below it the results, each captioned with its model or variant.

**Eagle** is never automatic. Only when the user asks ("put these in Eagle") and the project config names a library, the worker imports each image with `python3 <skill>/scripts/eagle-import.py --file <image> --library "<eagle.library>" --folder "<eagle.folder>" --name "<slug>-NN · <model>" --create-folder`. If Eagle has another library open, the script refuses and changes nothing: ask the user to open the project's library in Eagle, then rerun. Never switch Eagle's library yourself. `<skill>/references/eagle.md` covers failures and the API.

Then the **round report**: at most three lines, after every round, names copied from the config, never the lead's guess about itself:

```
Show, don't tell · round "<slug>" · <n> images
Lead: <lead.name> (<lead.harness>) · Worker: <worker.name> (<worker.harness>) · Image: <model> via <route>
Saved: <save_to>/<slug>-01…NN.png · compare sheet · Eagle: <library / folder | not imported>
```

When a run failed or stopped, line 3 becomes `Stopped: <reason>`. Send the compare sheet as the last thing in the reply (in Claude Code: `SendUserFile`, `display: render`). The user is the judge: no worker check of the images.

## 7. After the pick

- "Put #N in <place>": copy the image and its prompt file into that folder and say where it went.
- "Put these in Eagle": the Eagle step in 6. With no library in the project config, ask which library and folder, and save the answer there.
- "More like #N": run again from step 3 with #N added as a reference.
