# Image model routing

Merged from our own film tests (2026-11-12 to 11-20) and vendor model documentation. Our own tests outrank vendor or community claims.

How to prompt each model: `image-prompting/README.md` and the per-maker files.

## Evidence tags

| Tag | Meaning | Weight |
|---|---|---|
| **[tested]** | Our own runs | Highest |
| **[A]** | The maker publishes this ability for this exact version | Good basis for a candidate |
| **[report]** | Reseller, blog or community claims, untested by us | Weakest |

## How to route

Route each job by what it must hold, not by habit.

1. **The user's choice comes first.** A named model, format or count is kept. Otherwise pick one model and explain why in a line.
2. **Name the must-holds:** the one or two things the result fails without (a reference's layout and scale, a face's identity, exact text, a style reference, a long edit chain, a transparent background, a product's exact shape).
3. **Pick the model** whose strengths cover the must-holds and whose weaknesses miss them (within the routes configured in `~/.config/show-dont-tell/config.json`).
4. **Chain** when no single model covers two must-holds: the first model makes what it holds best, the second edits only the rest.
5. **References beat style** when an exact product, logo or text must survive: give the reference images and list what must not change. Without references the result is a concept, never "the real product".

## Common must-holds → first try

| Must-hold | First try | Notes |
|---|---|---|
| A given style reference, no layout to hold | GPT Image 2.6 | Default via Codex (`gen-image.sh`) |
| Exact text, counts, storyboard grid | GPT Image 2.6 | Read every word of required text before showing |
| Complex product geometry, detailed visual | GPT Image 2.6 | Attach references explicitly |
| Layout and scale of a layout reference | Seedream 5.5 | If available on a configured route; otherwise use GPT Image 2.6 with explicit layout-hold framing cues (`image-prompting/gpt-image-zoom-fixes.md`) |
| Photoreal likeness or environment | Nano Banana Pro / 2.1 | If available on a configured route; otherwise GPT Image 2.6 |

## The models we know best

### GPT Image 2.6 (OpenAI) — Default via Codex (`scripts/gen-image.sh`)
- **Strong:** follows written instructions to the letter (counts, "do not" rules, text) [report]; carries a given style reference best: our Daybreak style lock was approved on it [tested]; edits that change one thing and keep the rest held the framing 4/4 when the input frame was already right [tested].
- **Weak:** **pushes in on a layout reference**: figures came out 1.1-2.2x too big and the camera dropped unless compensated (`image-prompting/gpt-image-zoom-fixes.md`) [tested].
- **Route here when:** a style reference, text or strict instructions must hold, and the layout is free or already fixed in the input image.

### Seedream 5.5 (ByteDance)
- **Strong:** holds a layout reference's layout and scale (4/4 takes at 0.9-1.1x) [tested]; supports `<bbox>` coordinates per image in the prompt [A]; keeps untouched areas exact over long edit chains [A].
- **Weak:** draws literally what the words say; long prompts drop details [A]; style reference only partly met [tested].

### Nano Banana Pro / 2.1 (Google)
- **Strong:** natural photoreal look, up to 14 references (Pro), product and identity consistency across frames (2.1) [A].
- **Weak:** breaks explicit instructions more often [report]; on stylized film frames can drift too "animated" [tested].

## Keeping the evidence honest

- Save the real model, prompt, references, settings and result for each round.
- On a failure, fix the cause; don't hide it with endless retries.
