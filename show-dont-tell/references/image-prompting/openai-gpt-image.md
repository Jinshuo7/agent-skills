# OpenAI GPT Image 2 / gpt-image models (ChatGPT image generation) prompting (official sources)

Version note: the current official prompting guide is titled **“GPT-Image-2.6 prompting guide”** (with tabs for GPT-Image-2.6, GPT-Image-2.5, GPT-Image-2, GPT Image 1.5, GPT Image 1 (retired)); the API guide covers **GPT-Image-2.6 Sunburst / Flare**; the cookbook notebook is titled **“GPT Image Generation Models Prompting Guide”** and is written for `gpt-image-2` (“As of April 21, 2026”). Announcements: Images 2.6 (Nov 4, 2026), ChatGPT Images 2.5 (Sept 8, 2026), ChatGPT Images 2.0 (April 21, 2026).

## (a) Prompt structure, order, length, plain vs keyword style

- “Define the result. Name the subject and intended use… Specify the composition, aspect ratio, and important placement constraints. For complex requests, organize the prompt as **scene, subject, details, and constraints**, using labeled sections.” [https://platform.openai.com/docs/guides/image-prompting]
- Notebook version of the same ordering rule: “Write prompts in a consistent order (**background/scene → subject → key details → constraints**) and include the intended use (ad, UI mock, infographic) to set the ‘mode’ and level of polish. For complex requests, use short labeled segments or line breaks instead of one long paragraph.” [https://github.com/openai/openai-cookbook/blob/main/examples/multimodal/image-gen-models-prompting-guide.ipynb]
- Plain vs keyword/tag style is explicitly left to the writer: “Short prompts, descriptive paragraphs, JSON-like structures, instructions, and tags can all express the same intent. Choose the format that makes the requirements easiest to read and update rather than relying on special syntax.” [https://platform.openai.com/docs/guides/image-prompting]
- Notebook: “Use the format that is easiest to maintain… For production systems, prioritize a skimmable template over clever prompt syntax.” [https://github.com/openai/openai-cookbook/blob/main/examples/multimodal/image-gen-models-prompting-guide.ipynb]
- Length, consumer-facing guidance: “A good image prompt does not need to be long. In most cases, 1–3 clear sentences are enough.” [https://openai.com/academy/image-generation/]
- Length, iteration guidance: “Long prompts can work well, but debugging is easier when you start with a clean base prompt and refine with small, single-change follow-ups.” [https://github.com/openai/openai-cookbook/blob/main/examples/multimodal/image-gen-models-prompting-guide.ipynb]
- Overall edit recipe: “For edits, identify what should change and what must stay the same. Refine one thing at a time and inspect the result.” [https://platform.openai.com/docs/guides/image-prompting]

## (b) Using reference / input images

- “Assign roles to references. Identify each input **by number and purpose**: subject, style, clothing, or background. Explain how the inputs should combine and which elements should move where.” [https://platform.openai.com/docs/guides/image-prompting]
- “Multi-image inputs: Reference each input by **index and description** (‘Image 1: product photo… Image 2: style reference…’) and describe how they interact (‘apply Image 2’s style to Image 1’). When compositing, be explicit about which elements move where (‘put the bird from Image 1 on the elephant in Image 2’).” [https://github.com/openai/openai-cookbook/blob/main/examples/multimodal/image-gen-models-prompting-guide.ipynb]
- Same convention in Academy form: “Refer to each image by order and explain how they relate to each other. For example: ‘Image 1 is a photo of my desk setup. Image 2 is a style reference. Apply image 2’s clean, minimal illustration style to image 1, while keeping the same layout and objects.’” [https://openai.com/academy/image-generation/]
- How many: “You can use **one or more** images as a reference to generate a new image.” (that example uses “4 input images”) [https://platform.openai.com/docs/guides/image-generation]; the try-on example passes five inputs [https://github.com/openai/openai-cookbook/blob/main/examples/multimodal/image-gen-models-prompting-guide.ipynb]; Academy adds “a small set is usually easier to manage than a large one” [https://openai.com/academy/image-generation/]
- First-image specialness for markup: “The markup overlay applies only to the **first input image**. Any additional images serve as references.” [https://platform.openai.com/docs/guides/image-prompting]
- Naming which input dominates a layout: “Pass the scene photograph as image 1 and the dog photograph as image 2. Specify which element to move, its destination, and what must remain unchanged.” — example prompt: “Place the dog from the second image into the setting of image 1, right next to the woman, use the same style of lighting, composition and background. **Do not change anything else.**” [https://platform.openai.com/docs/guides/image-prompting]
- Spatial language for placement between inputs: “use clear spatial language—such as left, right, foreground, and background—to describe relationships.” [https://openai.com/academy/image-generation/]

## (c) Keeping a composition or layout from an input image (edit vs generate)

- Two paths exist: `Generations`: “Generate images from scratch based on a text prompt”; `Edits`: “Modify existing images using a new prompt, either partially or entirely.” [https://platform.openai.com/docs/guides/image-generation]
- API choice rule: “If you only need to generate or edit a single image from one prompt, the Image API is your best choice. If you want to build conversational, editable image experiences with GPT Image, go with the Responses API.” [https://platform.openai.com/docs/guides/image-generation]
- Forcing the mode in Responses: “set `action: “generate”` to always create a new image, or set `action: “edit”` to force editing when an image is in context.” [https://platform.openai.com/docs/guides/image-generation]
- The “change only X” pattern: “Separate changes from constraints. For edits, say **‘change only X’** and list the details to preserve, such as identity, geometry, **layout**, lighting, or labels.” [https://platform.openai.com/docs/guides/image-prompting]
- Notebook wording of the same, including the preserve-everything clause: “For edits, use ‘change only X’ + **‘keep everything else the same,’** and repeat the preserve list on each iteration to reduce drift.” [https://github.com/openai/openai-cookbook/blob/main/examples/multimodal/image-gen-models-prompting-guide.ipynb]
- Shortest official phrasing of that idea: “A prompt like ‘Change only X. Keep everything else exactly the same’ is often the clearest way to guide a precise edit.” [https://openai.com/academy/image-generation/]
- Sketch/line-art → rendered image (the closest official analogue to painting over a layout sketch): “Treat the prompt like a spec: preserve layout and perspective, then *add realism* by specifying plausible materials, lighting, and environment.” Example prompt: “Turn this drawing into a photorealistic image. **Preserve the exact layout, proportions, and perspective.** Choose realistic materials and lighting consistent with the sketch intent. Do not add new elements or text.” [https://platform.openai.com/docs/guides/image-prompting]
- Preserving layout while replacing content: “Translate the text in the infographic to Spanish. **Do not change any other aspect of the image.**” [https://platform.openai.com/docs/guides/image-prompting]
- Camera/framing/scale preservation wording the maker uses: “Preserve camera angle, room lighting, floor shadows, and surrounding objects. Keep all other aspects of the image unchanged.” [https://github.com/openai/openai-cookbook/blob/main/examples/multimodal/image-gen-models-prompting-guide.ipynb]
- “For precise local edits, also identify saturation, contrast, arrows, **camera angle**, and surrounding objects that must remain unchanged.” [https://platform.openai.com/docs/guides/image-prompting]
- Environmental changes only: “changing only environmental conditions—lighting direction/quality, shadows, atmosphere, precipitation, and ground wetness—while preserving identity, geometry, camera angle, and object placement so it still reads as the same original photo.” [https://github.com/openai/openai-cookbook/blob/main/examples/multimodal/image-gen-models-prompting-guide.ipynb]
- Localization by drawing on the input: “Draw a circle around the object you want to change, then describe the change in the prompt.” Example: “Recolor the striped vase inside the red circle… Keep its shape, the dried stems, and **the rest of the kitchen unchanged.** Remove the red circle from the finished photo.” [https://platform.openai.com/docs/guides/image-prompting]
- Camera specs are cues, not locks: “Treat camera specifications as cues for appearance, not a guarantee of exact physical simulation.” [https://platform.openai.com/docs/guides/image-prompting]
- Hard limit on exactness: “If part of an image must remain **pixel-identical**, composite the approved edit into the original.” [https://platform.openai.com/docs/guides/image-prompting]

## (d) Stopping the model from adding or inventing things

- “State exclusions such as unwanted text, logos, or watermarks.” [https://platform.openai.com/docs/guides/image-prompting]
- For text: “Ask for no extra text, then check spelling and legibility in the output.” [https://platform.openai.com/docs/guides/image-prompting]
- For sketch-to-render: “Include ‘do not add new elements/text’ to avoid creative reinterpretations.” [https://platform.openai.com/docs/guides/image-prompting]
- Notebook phrasing of exclusions: “State exclusions and invariants explicitly (e.g., ‘no watermark,’ ‘no extra text,’ ‘no logos/trademarks,’ ‘preserve identity/geometry/layout/brand elements’).” [https://github.com/openai/openai-cookbook/blob/main/examples/multimodal/image-gen-models-prompting-guide.ipynb]
- Academy: “Constraints are especially useful when something needs to stay fixed. If you do not want extra text, logos, or visual changes, state that directly.” [https://openai.com/academy/image-generation/]
- Exclusion lists are written as plain prohibitions, e.g. “No extra text, no watermarks, no unrelated logos.” [https://platform.openai.com/docs/guides/image-prompting]
- Anti-invention in a transparent-asset edit: “Do not add a solid backdrop, checkerboard, scenery, or shadow.” [https://platform.openai.com/docs/guides/image-prompting]
- Repetition is the stated anti-drift method: “repeat the preserve list on each iteration to reduce drift,” and “restate critical constraints if the result drifts.” [https://platform.openai.com/docs/guides/image-prompting] / [https://github.com/openai/openai-cookbook/blob/main/examples/multimodal/image-gen-models-prompting-guide.ipynb]
- One maker-admitted side effect of asking for more: “Higher complexity can increase latency and **introduce unwanted changes**, so compare results for your task.” [https://platform.openai.com/docs/guides/image-generation]
- Not in official sources: any statement about how the model parses negation itself (e.g. whether “no X” is honored differently from a positive restatement), or any ranked list of which negative instructions are more effective.

## (e) Style transfer from a style reference

- Minimal official example: “Use the same style from the input image and generate a man riding a motorcycle on a white background.” [https://platform.openai.com/docs/guides/image-prompting]
- Role assignment for style: “Assign the reference image a specific role: its palette, texture, or visual medium. Describe the new subject separately.” [https://platform.openai.com/docs/guides/image-prompting]
- Notebook definition: “Style transfer is useful when you want to keep the *visual language* of a reference image (palette, texture, brushwork, film grain, etc.) while changing the subject or scene. For best results, describe what must stay consistent (style cues) and what must change (new content), and add hard constraints like background, framing, and ‘no extra elements’ to prevent drift.” [https://github.com/openai/openai-cookbook/blob/main/examples/multimodal/image-gen-models-prompting-guide.ipynb]
- Style reference combined with layout preservation: “‘Image 2 is a style reference. Apply image 2’s clean, minimal illustration style to image 1, while keeping the same layout and objects.’” [https://openai.com/academy/image-generation/]
- Style-reference drift control in iteration: “References such as ‘same style as before’ can carry context, but restate critical constraints if the result drifts.” [https://platform.openai.com/docs/guides/image-prompting]
- Maker’s own claim about style adherence in the announcement: “It’s also better at reflecting visual styles, so your images are more aligned with your artistic vision.” [https://openai.com/index/introducing-chatgpt-images-2-5]

## (f) Text in images

- “Specify exact text. **Put required wording in quotes** and describe its position and typography. Spell unusual words or brand names letter by letter when needed.” [https://platform.openai.com/docs/guides/image-prompting]
- “Quote the required copy and tell the model **how many times** it should appear.” Example: “Render the tagline exactly once, clearly and legibly, integrated into the ad layout. No extra text, no watermarks, no unrelated logos.” [https://platform.openai.com/docs/guides/image-prompting]
- Notebook: “Put literal text in **quotes** or **ALL CAPS** and specify typography details (font style, size, color, placement) as constraints. For tricky words (brand names, uncommon spellings), spell them out letter-by-letter to improve character accuracy. Use `medium` or `high` quality for small text, dense information panels, and multi-font layouts.” [https://github.com/openai/openai-cookbook/blob/main/examples/multimodal/image-gen-models-prompting-guide.ipynb]
- Academy, with a point size: “‘Add the headline “WEEKLY PLAN” in bold sans-serif, white, centered at the top, 72pt. No other text.’”; also “Keep text short” and “spell out letter-by-letter (e.g., ‘S-T-R-I-P-E’)”. [https://openai.com/academy/image-generation/]
- Dense text: “For dense layouts or heavy in-image text, emphasize ‘sharp text rendering,’ and consider polishing in design tools if needed.” [https://openai.com/academy/image-generation/]
- Quality/complexity lever: “Higher complexity can help with **dense text**, complex layouts, and relationships between objects,” and “If the layout is correct but small text is hard to read, compare quality settings at the same complexity.” [https://platform.openai.com/docs/guides/image-generation] / [https://platform.openai.com/docs/guides/image-prompting]
- Stated limit: “Although significantly improved, the model can still struggle with precise text placement and clarity.” [https://platform.openai.com/docs/guides/image-generation]

## (g) Known limits and failure modes the maker admits

- “**Composition Control:** Despite improved instruction following, the model may have difficulty placing elements precisely in structured or layout-sensitive compositions.” [https://platform.openai.com/docs/guides/image-generation]
- “**Consistency:** While capable of producing consistent imagery, the model may occasionally struggle to maintain visual consistency for recurring characters or brand elements across multiple generations.” [https://platform.openai.com/docs/guides/image-generation]
- “**Latency:** Complex prompts may take up to 2 minutes to process.” [https://platform.openai.com/docs/guides/image-generation]
- Camera specs are approximate: “detailed camera specs may be interpreted loosely, so use them mainly for high-level look and composition rather than exact physical simulation.” [https://github.com/openai/openai-cookbook/blob/main/examples/multimodal/image-gen-models-prompting-guide.ipynb]
- Pixel-exact regions cannot be guaranteed: “If part of an image must remain pixel-identical, composite the approved edit into the original.” [https://platform.openai.com/docs/guides/image-prompting]
- Selection-based edits bleed: “Highlights are not always precise, and edits may extend beyond the area you selected.” [https://help.openai.com/en/articles/11084440-images-in-chatgpt]
- Extra planning costs fidelity: “Higher complexity can increase latency and introduce unwanted changes.” [https://platform.openai.com/docs/guides/image-generation]
- Self-check list the maker gives for catching these: “Did the edit change only what you requested?”; “Do identities, product shapes, labels, and reference details remain intact?”; “Can you read every word…?” [https://platform.openai.com/docs/guides/image-prompting]
- Maker-stated direction of improvement rather than a guarantee: “Images 2.5 is better at editing only what you’ve asked for, while keeping the rest of the details the same,” and “you can update a single element… while preserving the subject, composition, and brand treatment around it.” [https://openai.com/index/introducing-chatgpt-images-2-5]
- Also announced for 2.6: “Image markup… comes to the API so teams can pinpoint exactly where to make specific changes,” plus a new `complexity` parameter, with the recommendation “For most editing tasks, we recommend low complexity for faster edits.” [https://openai.com/index/introducing-images-2-6]

## Sources read

- https://platform.openai.com/docs/guides/image-prompting (and its `…/image-prompting.md` source; content titled “GPT-Image-2.6 prompting guide” with 2.5 / 2 / 1.5 / 1 tabs)
- https://platform.openai.com/docs/guides/image-generation (and its `…/image-generation.md` source)
- https://developers.openai.com/api/docs/guides/image-prompting.md (same page on the developers host)
- https://developers.openai.com/cookbook/examples/multimodal/image-gen-models-prompting-guide.md (resolves to the same Image prompting page)
- https://cookbook.openai.com/examples/multimodal/image-gen-models-prompting-guide
- https://cookbook.openai.com/llms.txt
- https://developers.openai.com/llms.txt
- https://platform.openai.com/llms.txt (404)
- https://github.com/openai/openai-cookbook/blob/main/examples/multimodal/image-gen-models-prompting-guide.ipynb
- https://raw.githubusercontent.com/openai/openai-cookbook/main/examples/multimodal/image-gen-models-prompting-guide.ipynb
- https://openai.com/index/introducing-images-2-6
- https://openai.com/index/introducing-chatgpt-images-2-5
- https://openai.com/index/introducing-chatgpt-images-2-0
- https://openai.com/index/introducing-gpt-image-2/ (404 — no such slug)
- https://openai.com/news/rss.xml (used only to find the official article slugs)
- https://openai.com/academy/image-generation/
- https://help.openai.com/en/articles/11084440-images-in-chatgpt
- https://help.openai.com/en/ and https://help.openai.com/en/collections/3742473-chatgpt (index browsing only)
- https://openai.com/index/ (index browsing only)

## What slowed me down

- `openai.com/index`, `openai.com/academy`, and `help.openai.com` all returned HTTP 403 to `curl` (bot protection), so those pages had to be read through a headless browser session; the article slugs also 404 if guessed (`/index/introducing-gpt-image-2/` does not exist — the real slugs are `introducing-images-2-6`, `introducing-chatgpt-images-2-5`, `introducing-chatgpt-images-2-0`). I found them by reading the official RSS feed.
- `platform.openai.com/llms.txt` (the index the docs `.md` pages point to) is a 404; the working index is on `developers.openai.com`.
- Platform docs are client-rendered, so the HTML is mostly navigation; appending `.md` to the docs URL gives clean text. That is how the guide and API pages were read.
- The `.md` docs page bundles all five model tabs in one file, so the same section headings repeat (Overview, Prompting fundamentals, Transfer a visual style, …) — it takes care to attribute a quote to 2.6 vs 2.5 vs `gpt-image-2`.
- `cookbook.openai.com/examples/multimodal/image-gen-models-prompting-guide` no longer serves the notebook; it now serves the docs “Image prompting” page. The `gpt-image-2`-era wording (e.g. “keep everything else the same”, the index-based “Image 1 / Image 2” phrasing, the style-transfer paragraph) only survives in the GitHub notebook, which I had to fetch as raw JSON and flatten.
- The notebook has a copy/paste defect: the “Object Removal” section carries the paragraph “Person-in-scene compositing is useful for storyboards…” and shares it with the next section, so section prose and prompts do not line up. I quoted only prompts that match their section heading.
- The `introducing-chatgpt-images-2-0` article renders almost no body text (the content is a media carousel), so it contributed no quotable guidance.
