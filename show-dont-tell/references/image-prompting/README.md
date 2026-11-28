# Prompting image models from official sources (2026-11-20)

Researched by the worker (DeepSeek) from the makers' own pages only; checked by the lead. Full quotes with URLs, one file per maker:
`openai-gpt-image.md` (GPT Image 2.6 guide), `google-nano-banana.md` (Nano Banana 2.1 / Pro), `bytedance-seedream.md` (Seedream 5.5 / 5.0).

## What all three agree on
- **A sketch-to-frame job is an EDIT of the sketch, not a new generation.** Each maker's own sketch recipe:
  - OpenAI: "Preserve the exact layout, proportions, and perspective... Do not add new elements or text."
  - Google: "Preserve the original composition but render it with..."
  - Seedream: "Keep the composition unchanged. Remove all sketch lines."
- **Number every input image and give each one role**: "Image 1 is ..., Image 2 is ...". Then say how they combine.
- **Name what to keep**: the preserve list (layout, camera angle, proportions, object placement). Repeat it on every run.
- Camera words (lens, height) are loose cues. No model promises an exact layout. For pixel-exact areas, composite afterwards.

## Where they differ
| | GPT Image 2.6 | Nano Banana 2.1 / Pro | Seedream 5.5 |
|---|---|---|---|
| Prompt shape | labelled sections: scene, subject, details, constraints | narrative; be direct for edits | short and concrete; long prompts drop details |
| Unwanted things | plain exclusions ("no extra text", "do not add new elements") | describe what you want ("bare concrete floor"), not "no X" | plain sentences ("do not change other layout") |
| Placing things | left/right/foreground words | photographic terms | list the elements in depth order (front to back); `<bbox>x0 y0 x1 y1</bbox>` with Image N, on a 0-999 grid |
| References | "a small set is easier"; markup applies only to image 1 | up to 14; Pro: up to 5 characters and 3 style refs; 2.1: 4 characters and no style-ref slot | up to 10 on 5.5 |
| Admitted limits | "may have difficulty placing elements precisely in layout-sensitive compositions" | no composition lock; the canvas follows the last image's aspect ratio | multi-turn drift; overlong prompts |

## How we apply this (Daybreak 6.1 test r3)
- The colour sketch (`guide.png`) is **image 1** and is the image being edited. The style reference moves to image 2 (`--no-auto-refs`).
- Light is described by its sources. Every patch of light on the floor sits under a lamp the viewer can see, so the model never gets loose circles (the user's note: circles with no source read as a second silo door).
- Seedream also gets bbox coordinates for each coloured shape, measured from `guide.png`.

## GPT Image zoom-in (research 2026-11-20): `gpt-image-zoom-fixes.md`
Nobody reports a setting that pins composition. What users confirm works, all usable in a web UI:
1. **Pad the sketch first:** put a border around the sketch on the output canvas, ask the model to fill the border, then crop the border off. Our `zoom-out.sh` does the same thing, but after styling instead of before.
2. **A second pass in the same chat:** "perform a slight zoom out on this image to fix the cropped borders" (two users confirm; quote spot-checked by the lead).
3. **Positive framing words instead of "do not crop":** wide-angle, wide shot, figures small in frame, generous empty space.
Note: API settings `size`, `complexity: low` and `markup` are not confirmed for this problem anyway. No report fixes the camera dropping lower.
Tested 2026-11-20 on Daybreak 6.1 (GPT Image 2.6, 2 takes each; sheet `DayBreak/show/2026-11-20/r4-compare.jpg`):
- Padded sketch: 1.3-1.4x / 1.7x (no better than r3).
- "Slight zoom out" second pass in a new chat: only 3-10 % smaller.
- **Positive framing words**: 1.1-1.2x / 1.3-1.5x, the best result; the wall line lands on target.
None reached 1.15x on both figures. Seedream 5.5 still holds the scale best.
- **Two-step route works for framing (2026-11-20, r5):** a Seedream 5.5 frame (layout held) as image 1, restyled by GPT Image 2.6 with a "change only style + X / keep exactly the same" prompt: all 4 takes kept the framing (0.9-1.07x) and came out at 4K. The style is only partly flat, and the ceiling-lamp count is not exact. Sheet `DayBreak/show/2026-11-20/r5-compare.jpg`.
