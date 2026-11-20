# Genspark: highest free settings per model

Probed 2026-11-13 on the user's Genspark Plus plan with `_studio/tools/genspark-probe-free.py`. Raw result: `_studio/tools/genspark-free-limits.json`. Rerun the probe when the plan changes or Genspark adds models (it generates nothing and spends nothing).

## How the limit works

- Genspark gates paid settings itself. Picking a model, size or quality that isn't free on the plan opens a pop-up: "This option uses credits … Continuing will use credits", with a "Continue with Credits" button and a "don't ask again" box. **Never click either.** The probe and `genspark-batch.py` close it with the × and stop.
- Plan page (2026-11-13): "AI Chat and AI Image stay credit-free through Dec 31, 2026 while you're subscribed." After that date the rules may change: rerun the probe in January.
- No image cap is shown. The usage page only counts (341 AI Image generations this cycle, Oct 15 – Nov 15) and logs every image as "0 credits, Free". The weekly "Free Quota" (97% left, resets weekly) is for Standard-mode agent tasks and didn't move with our images. No 5-hour or hourly limit appeared anywhere.
- Available credits are 0, so nothing could be charged by mistake anyway; a paid job would fail.
- The × multipliers in the model menu (e.g. Nano Banana Pro 2.48×) are credit prices for paid use. They don't limit free use.
- Generation count 1, 2 and 4 are free on every model.

Verified: GPT Image 2.6 at 16:9 4K High generated a 3840x2160 image (`_studio/test/genspark/limits/gpt26-4k-high.png`). The usage page logged it as an AI Image at 0 credits, the image counter went 341 → 342, and the weekly Free Quota stayed at 97%.

## Highest free setting

| Model | Multiplier | Highest free | Costs credits |
|---|---|---|---|
| GPT Image 2.6 | 1× | **4K, quality High** | quality X-High, Max |
| GPT Image 2.5 | 1× | 4K, quality High | X-High, Max |
| GPT Image 2 | 1× | 4K, quality Medium | High |
| Nano Banana Pro | 2.48× | **2K** | 4K |
| Nano Banana 2.1 | 0.63× | 2K | 4K |
| Nano Banana 2 Flash Lite | 0.63× | (no size setting) | none |
| Seedream 5.5 | 0.3× | **1K** | 2K |
| Seedream 5.0 Pro | 0.85× | 2K | none |
| Seedream v5 Lite | 0.67× | 3K | none |
| FLUX 3 Image | 0.89× | 2K | 4K |
| Grok Imagine Image 2.0 | 1.3× | 2K | none |
| Qwen Image 3 | 1.48× | (no size setting) | none |
| Ideogram V4.5 | 2.22× | quality High | none |
| Ideogram V4, Recraft V4.1, Krea 2 Turbo, Z-Image Turbo | | (no size setting) | none |

Not probed: the tools (Recraft Clarity Upscale, Bria Background Remover, Text Removal, Flux Pro Erase).

## What this means for us

- Daybreak (GPT Image 2.6): run Genspark jobs at `16:9 4K High`. Codex has no such choice.
- Seedream 5.5 is free only at 1K; for a bigger free Seedream use 5.0 Pro at 2K, or upscale.
- Nano Banana Pro and 2.1 max out at 2K free.
