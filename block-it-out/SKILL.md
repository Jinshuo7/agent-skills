---
name: block-it-out
description: Blender blockout (a rough sketch) of a film shot: basic set, a real camera and lens, and one flat colour per character and key prop (posed mannequins for photos, blocks for video), rendered as a guide image, a colour legend and an optional blocking clip, so any image or video model keeps a fixed layout, camera, pose and cast. Stops at the Blender renders; generating images or video is a separate step. Use when a shot's composition, staging, eyelines or camera move must be locked before generating stills or video, or the user asks for a blockout, layout guide or Blender reference.
---

# Block it out

A **blockout** pins geography, camera and pose; the image or video model only adds style. This skill ends with the Blender renders and the prompt lines to use with them. It does not generate images or video, so it works with any image or video tool. Keep it plain: boxes, mannequins, one camera. Extra detail confuses the model.

Path: `B="/Volumes/Jinshuo Edit_A/AI Filmmaker/_studio/blender"`. Always call the script by this full path (films may sit deeper, e.g. `Projects/<Film>/`). Run everything from the film folder.

Read `$B/README.md` before writing a spec: it holds the spec fields, coordinates, bearings, poses and joints.

## 0. Photo or video?

Ask first, unless the conversation already says: **is this shot for a photo or a video?** It decides the figures and the outputs.

| | Photo | Video |
|---|---|---|
| Figures | coloured mannequins (`"figures": "mannequin"` + `"color"`), full pose detail: joints, eyelines, hand placement | coloured blocks (`"figures": "block"`): one flat colour per character, a nose block for facing, no limbs. The video model does the acting. |
| Movement | none | blocks slide along paths, fold to sit, tip to lie; camera keys as needed |
| Send to models | `guide.png` and the references, with the `legend.txt` prompt line | the styled first frame, `clip.mp4` (the blocking video) and `plan.png` (top view), with the `legend.txt` prompt line |
| Depth | off (`--only guide,plan`) unless the user asks | off (`--only guide,plan,clip`) unless the user asks |

**Colour and legend (both modes, studio decision 2026-11-18).** Every character gets a `"color"` and a `"ref"` (e.g. `"image 3"`, the reference image that plays them). Every key prop the shot depends on (a weapon, a hero object) gets the same, using a `rod` set item for swords, spears and poles. The run writes `legend.txt`, which maps each colour to its reference, like the key on a map. Pick colours far from the characters' costumes. The legend fixes identity and prop colour; grey mannequins without a legend let the model swap or merge characters.

Suggest each colour's reference from the film's locked picks (face lock, turnaround or outfit image; read through `eagle.py picks`): one image per colour, made to the boring photo rule (`clip-craft`). Image numbers follow the order the references will actually be attached: in a film with `style/auto-refs.txt` its style reference is image 1 and the guide image 2; without one the guide is image 1. Count from the real job before you write `ref` values. A figure whose head turns away from the camera (three-quarter, profile) takes the character's turnaround sheet (`turnaround-sheet`), not a front view: the model copies the facing it sees in the reference, and a turned close-up bust overshoots the turn and tightens the framing. The user confirms the list before the render.

## 1. Find the shot in the shot list, then gather it

The blockout serves the film's shot list; it never invents its own shots. Look for the shot list first (the film's `status.md` says where it is).

- **Shot list exists:** find the shot the user means in it. Its ID is `<shot>`, used for the spec name and output folder (e.g. shot `12A` → `blockout/12A.json`). Take the shot's size, lens, framing and action from it. If the user's words don't match a listed shot, ask which one it is, or whether it's a new shot to add to the list.
- **No shot list:** don't name files yourself. Ask: "There's no shot list yet. Is it okay if I name the blockouts by sequence (`sc01-sh01`, `sc01-sh02`, …), or how would you like them named?" Wait for the answer before you write a spec.

Then gather the shot from the conversation and the film's files (shot list, location spec / floor plan, the scene's text): the set and its sizes, who is where, facing and looking at whom, each person's pose and height, the lens and camera position, and any move (camera keys, people walking). When the film has a location spec, take sizes and door positions from it, never invented.

### Director and sketch artist

The user is the director and describes the shot in words; you draw it. Facts that change the picture are the user's; small fillers (chair height, shelf size) you choose.

1. **Read it back.** One short paragraph saying what you will draw, then a list of what you are assuming. Test the words against the geometry before you ask anything: "behind his left shoulder" and "he is frame left, aiming frame right" cannot both hold. Name any such clash and offer the ways out.
2. **Story facts** (who, where, doing what, facing whom, which props matter, what is behind each person): ask what the words and files leave open, in one `AskUserQuestion` batch, with options for each. Facts the shot list or location spec already gives are not asked.
3. **Camera facts** (shot size, lens, camera height, angle): show, not ask. Render 2-3 variants (`--only guide`, about 4 s each) that differ on the open camera facts, send them side by side, and let the user pick one by eye.
4. **Colours and references** (step 0): confirm, then render the full set (step 2), check (step 3), and take corrections in words ("zoom out", "blue taller than red") until the user says the frame is right.

**Batch (a shot list):** ask the shared facts once per scene (set, camera height and lens family, cast colours and references), then only each shot's own gaps. Then write a **scene plan** before any shot spec: the shared set, the scene line (step 5), and for each beat where every person stands and faces, in metres. Each shot is then a camera on that plan, so people keep their sides from shot to shot. Read the shot list against the plan: in a reverse angle, "toward the truck" and "frame left" can contradict; name the clash and ask.
**Video:** the same, plus duration, who moves where and when, and the camera move.

## 2. Write the spec and render

**Who does what (two speeds):**

| | Live (one shot, user waiting) | Batch (a whole scene from the shot list, user away) |
|---|---|---|
| Spec | lead writes it directly (a spec is ~1 KB; briefing a worker costs as much) | lead writes the scene plan (step 1); cheap worker writes one spec per call from the plan, the shot list and `$B/README.md`, listing what it assumed (`~/.claude/guides/worker-briefing.md`; `--thinking low`, calls in parallel; a five-shot call got cut off); lead checks each spec against the plan |
| Check (step 3) | visual-checker subagent (~1 min) | cheap worker with image input (pi: `@guide.png @plan.png @sheet.jpg`), up to about 4 images per call; more images or a big cast go to the visual-checker |
| Lead's part | judgment, spec, fixes | spot-check every FAIL and one PASS image before showing the user |

Examples for batch specs and for the worker's check prompt: `templates/block-sit.json` (video), `templates/two-in-room.json` (photo).

Write `blockout/<shot>.json` in the film folder (one file per shot; `templates/` in `$B` has examples). Then:

```bash
"$B/blockout.sh" blockout/<shot>.json
```

Output goes to `blockout/<shot>/`: `guide.png`, `depth.png`, `plan.png`, plus `last.png` and `clip.mp4` when anything is keyed, and `legend.txt` when anything has a colour. Pass on any `WARNING` lines from the run, and fix the spec for them.

Before any visual check, read `info.json` `"measure"` (README: Measurements): each figure's height, centre, head position (`head_x_pct`, `head_y_pct`) and feet as % of frame, whether it is cropped or hidden, each coloured prop's visibility, the horizon. Fix framing by these numbers first; it takes seconds and no checker round. Where a face should sit, give the checker `head_x_pct`; `x_pct` is the middle of the whole outline, which a seated or turned pose pulls off the head.

Spec habits that save check rounds (self-test 2026-11-18):
- Every hand that touches something (a prop, a table, another person) gets `reach`, not hand-set joint angles.
- Write each figure's `note`, and a `note` on each coloured prop that points somewhere (vehicle, weapon), in frame words (frame left/right, toward/away from camera) with what it does. The note goes into the image prompt, so it carries what clay can't show: small head nods, leans along the lens axis.
- Aim a weapon well off the lens axis, or it hides behind the body.
- Keep set items a few cm off walls; touching faces flicker.

## 3. Check

Send `guide.png` and `plan.png` (and a frame sheet of the clip: `ffmpeg -i clip.mp4 -vf "select='not(mod(n\,24))',scale=480:-1,tile=4x2" -frames:v 1 sheet.jpg`) to the checker named for this speed in step 2 (live: **visual-checker** subagent) with the intended shot spelled out as claims it can match one by one: who stands where, facing whom, pose, what's in frame. Fix the spec and re-render until it passes. Done = the checker confirms placement, facing, eyelines and framing match the shot.

**Agreement check.** Also give the checker each figure's `note` and its `face` bearing (0 = away, 90 = frame right, 180 = at camera, 270 = frame left). The checker first writes what the render shows, in its own words: for each figure, where the body faces, where the eyes look, where each gun or sword points, and the pose. Then it compares that description with each note, each bearing and the shot list. Done = every facing and every weapon direction agree in all three. Fix a mismatch in the spec. A prompt never corrects the sketch (shot 1.2: Rhino `face 205`, at the camera, while his note said he fires frame left).

Tell the checker that diagonal shapes on walls are cast shadows and that small nods and leans along the lens axis don't need to read. After three check rounds on one shot, stop chasing what clay can't show: make sure the note says it, and pass the shot with that line in the report.

## 4. Show the user

`SendUserFile` the `guide.png` and `plan.png` (and `clip.mp4`), `display: render`, with one line naming lens, camera height and what's locked. The layout is the user's call: wait for their OK or changes.

## 5. Hand off

Stop here. Give the user the approved files and the lines to put in their own prompt; don't start an image or video generation from this skill.

- **Photo:** `guide.png` plus one reference per colour, attached in the order of their `ref` image numbers (legend order can differ). The prompt, in this order:
  1. the last line of `legend.txt`;
  2. its `Sizes in the sketch` line;
  3. > Match the camera, lens, layout, figure sizes and poses of the sketch exactly; keep the figures as small in frame as they are in the sketch. The sketch carries no style.
  4. `Blocking (as in the sketch):` each figure's `<name>: <note>.`, and each coloured prop whose direction matters (a vehicle's nose, a weapon's aim). With three or more people, open it with `From frame left to frame right: <names>.` Colours alone don't hold identity in a crowd, and without notes the model turns small figures toward the camera and copies a prop's direction from its reference;
  5. the scene line: the place, what each key set piece looks like ("an iron lamp post with a lantern top") and the light. Grey set boxes carry no look, so an unnamed set stays grey or drifts. In a batch, the line is word for word the same in every shot. The line holds the set, not the cast: name the pieces the shot needs and stop there, since a busy line brings in shop signs and extra people;
  6. the story moment. In a reverse angle, open it with what is near and what is far ("camera on the fence side: the fence across the near foreground, the track far behind them"); grey boxes don't say which is which and the model falls back on the usual view. Light and weather belong to line 5 only.

  Without coloured figures (an empty set), use only line 3, with "grey reference" for "sketch".
- **Video:** first style the first frame into a still (the photo route above), then send that still, `clip.mp4` and `plan.png` to the video model with the last line of `legend.txt` and "Reference the character's actions and camera language from @Video." Label `plan.png` as the blocking reference (`clip-craft` prompt rules).

If the user asks for the generation next, that is a separate step with whatever image or video tool they use (in this studio: `show-dont-tell`).

## 6. Record

Note in the film's `status.md` which shots have blockouts. Results that teach something about the method (a model ignoring the guide, a pose that reads badly) go into the handoff or `_studio/notes/workflow.md`.
