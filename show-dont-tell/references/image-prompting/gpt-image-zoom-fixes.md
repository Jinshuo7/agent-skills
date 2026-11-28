# GPT Image zoom-in / reframing fixes

Short version: no source I could open reports a single setting that reliably pins composition when you repaint a sketch. What people do report is (a) removing the size/aspect mismatch that forces a crop, (b) putting the frame edge *inside* the input image so the model has nothing to crop to, (c) a second "zoom out" pass, and (d) replacing "do not crop" with positive camera/scale language. Nobody reports a fix for the *lowered camera* specifically; the closest is one unanswered forum report of edits changing camera angle.

| Fix | Needs API? | Evidence (confirmed / unconfirmed, how many reports) | URL |
|---|---|---|---|
| Set output `size` to the sketch's own pixel geometry (16:9 → e.g. `1536x864`; multiples of 16, ratio ≤ 3:1) so the model never has to fit a 16:9 drawing into 3:2 | Yes (`size` param) | Confirmed — official parameter/constraint docs + 2 practitioner reports that matching input/output size improves adherence | https://developers.openai.com/api/docs/guides/image-generation |
| Pad / letterbox the sketch onto the target canvas yourself (border in the image or transparency), repaint, then crop the border back off | No for the padding (any image editor); API only if you must also force `size` | Confirmed — 3 people in one thread, thread resolves with "we solved it" | https://community.openai.com/t/why-gpt-image-api-crops-original-please-support-flexible-aspect-ratios/1244785 |
| Second pass: "perform a slight zoom out on this image to fix the cropped borders" / "extend the canvas, change nothing else" | No — chat UI | Confirmed — 2 independent users, one says it fixed days of failure | https://community.openai.com/t/how-do-i-get-gpt-to-provide-images-that-are-not-cropped/1279519 |
| Drop "do not crop / preserve layout"; state camera + scale positively ("wide angle", "full body, head to toe", "5% margin", "generous empty space") | No — chat UI | Confirmed — 2 independent threads (one reports the fix worked; one analyses why "no cropping" alone fails) | https://community.openai.com/t/gpt-image-1-bias-towards-cropping-with-1024x1024-aspect-ratio/1318395 |
| `complexity: "low"` on GPT-Image-2.6 (default is `high`) | Yes (`complexity`, 2.6 only) | Unconfirmed for this symptom — official docs say high complexity "can introduce unwanted changes"; no user report of it fixing reframing | https://developers.openai.com/api/docs/guides/image-generation |
| `markup`: transparent PNG overlay, same pixel dimensions as input image 1, to draw the frame/crop marks you want kept | Yes (`markup`, 2.6 only) | Unconfirmed for framing — official feature, documented only for pointing at objects | https://developers.openai.com/cookbook/examples/multimodal/image-gen-models-prompting-guide |
| `input_fidelity: "high"` (gpt-image-1 / 1.5 only; must be omitted on 2.x) | Yes | Unconfirmed — 1 practitioner report that it alone made a 1.5 edit keep 1536×1024 and keep the photo | https://github.com/metadist/synaplan/issues/2404 |
| Send two images: clean frame as image 1, sketch-over-frame as image 2 (image 1 is the one mask/fidelity apply to) | Yes (multi-image edit) | Unconfirmed — 1 author, who explicitly marks it "experiment to run" | https://github.com/mattwestbrooke/ComfyComp_GPTedit/issues/4 |
| Mask over the whole frame to freeze layout | Yes | Reported *not* to work — official docs plus 3 forum users | https://community.openai.com/t/mask-is-completely-ignored-in-the-image-edit-api/1350867 |

## Fix notes

**Exact output size.** The docs state the size constraints plainly: "Sunburst and Flare also support custom dimensions as WIDTHxHEIGHT strings, such as 1536x864. Width and height must be multiples of 16, the aspect ratio must be between 1:3 and 3:1" (https://developers.openai.com/api/docs/guides/image-generation). Practitioners tie this to layout drift; `_j` recommends "Constraining input image + mask to the exact output resolution also specified" and keeping the ratio modest because the model re-renders rather than pastes (https://community.openai.com/t/gpt-image-api-how-can-i-reliably-edit-only-the-masked-selected-area-while-preserving-everything-else/1389833). In his editor he calls it "matching API I/O sizes with masking is for good revision adherence" (https://community.openai.com/t/gpt-image-2-image-creator-and-editor-app-python-desktop-ui-download-in-latest-j-reply/1370104). Caveat: on GPT-Image-2.5, edits apparently keep the input's own orientation instead of snapping to 3 presets — "The model keeps the input orientation (observed today: 4:3 input → 1448×1086 with Flare)" (https://github.com/metadist/synaplan/issues/2404) — so on 2.x a size mismatch is less likely to be your cause, which leaves re-framing as the explanation.

**Padding the input.** The clearest fix in the corpus. `_j`: "So wrap the input image in more white space, padding it out in all dimensions, at the same time that you make it conformant to an existing size so all that needs to be done is 'edit'" (https://community.openai.com/t/why-gpt-image-api-crops-original-please-support-flexible-aspect-ratios/1244785). `merefield` then found the missing half of the prompt: "Prompt: 'make the bus navy blue, fill out the full picture with the background' … Conclusion, this is a reasonable technique" and later "As a team, we solved it." Same thread contains the PIL recipe for centring an arbitrary image on a 1024×1536 white canvas. Note the dissenting refinement from `_j` later: avoid padding hints *in the mask*, and "trim up the input image by any excess to align the two dimensions within the 16px capability" (https://community.openai.com/t/gpt-image-api-how-can-i-reliably-edit-only-the-masked-selected-area-while-preserving-everything-else/1389833).

**Second "zoom out" pass.** The one-line fix with independent confirmation. `aprendendo.next`: "Try this follow up prompt: perform a slight zoom out on this image to fix the cropped borders"; the OP confirms, and weeks later another user: "worked for me like wtf, i got messed by the bot for several days and then you single sentence fixed it entirely" (https://community.openai.com/t/how-do-i-get-gpt-to-provide-images-that-are-not-cropped/1279519).

**Framing words instead of prohibitions.** The OP of the cropping thread says prohibitions failed ("even if I add e.g. 'full body shot, entire subject in frame'") and that the fix was framing vocabulary: "Thanks!! The square image/wide angle and full body / head to toe seemed to do the trick" (https://community.openai.com/t/gpt-image-1-bias-towards-cropping-with-1024x1024-aspect-ratio/1318395). A parallel thread diagnoses the same thing: the model "knows how to draw the blade, but not how to frame it… unless you force vertical layout with extra whitespace", and the accepted prompt adds explicit margins (https://community.openai.com/t/how-to-stop-odd-cropping-in-image-gen/1230077).

**`complexity`.** Official, but about "unwanted changes" in general, not reframing: "Lower complexity can suit focused edits… Higher complexity can increase latency and introduce unwanted changes, so compare results for your task." It defaults to `high` (https://developers.openai.com/api/docs/guides/image-generation). No forum or GitHub report of it fixing a zoom-in.

**`markup`.** Documented as an annotation layer for edits: "Use the original kitchen photo for image and the transparent circle overlay for markup. Both files are 1200 × 900 pixels… The markup overlay applies only to the first input image… Omit mask when you send markup" (https://developers.openai.com/cookbook/examples/multimodal/image-gen-models-prompting-guide). Mechanically this is the only official way to put lines into the edit request that the model is told to treat as spatial intent; no one in the corpus reports using it to hold a frame.

**`input_fidelity`.** Only meaningful on gpt-image-1/1.5; for 2.x the docs say "omit this parameter; the API doesn't allow changing it because the model processes every image input at high fidelity automatically" (https://developers.openai.com/api/docs/guides/image-generation). The single report: "The original report — a gpt-image-1.5 edit that redrew the photo at 1024×1024 — comes from the missing input_fidelity on gpt-image-1.x (direct test: input_fidelity: "high" alone → 1536×1024, photo kept)" (https://github.com/metadist/synaplan/issues/2404). That is a size/redraw fix, not a framing fix, and it is one person.

**Two-image encoding (clean frame + sketch overlay).** A VFX pipeline spec, not a test result: "Image 1 is the clean frame, because the mask and input_fidelity apply to the first image. Image 2 is the sketch over the frame, used as an annotated reference", and "Burning the sketch into a single image is the weakest default" (https://github.com/mattwestbrooke/ComfyComp_GPTedit/issues/4). The author lists the comparison as an "Experiment to run", so treat as unconfirmed.

**Masks do not lock the layout.** Official: "Masking with GPT Image is entirely prompt-based. The model uses the mask as guidance, but may not follow its exact shape with complete precision" (https://developers.openai.com/api/docs/guides/image-generation). Forum: "The mask serves as guidance only… The model still regenerates the whole image" (https://community.openai.com/t/mask-is-completely-ignored-in-the-image-edit-api/1350867).

**On your two specific symptoms:** the size/crop mechanism is well attested for the tightening (an HN commenter on a model comparison: "Gpt-image-1 is a lot stricter in the supported output resolutions so it's using a cropped image", https://news.ycombinator.com/item?id=45219802). I found no source at all on the camera height lowering; the nearest thing is one unanswered forum report, "gpt-image-1 changing camera angle when editing an image… in the past few weeks almost all generated images have been switching camera angles", with zero replies (https://community.openai.com/t/gpt-image-1-changing-camera-angle-when-editing-an-image/1360594).

## Best bets for a web UI (no API)

- Pre-pad the sketch yourself before uploading: place the 16:9 drawing on a canvas whose border is in the scene's own background colour, sized to the exact output ratio/size, and say "fill the border with the same background". Then crop the border off. This is the only trick in the corpus with several independent users behind it.
- Always run a second pass, in the same chat, as a one-liner: "perform a slight zoom out on this image to fix the cropped borders" — two independent users report it working, and it needs nothing but the text box.
- Delete "preserve the exact layout / do not crop" and replace it with camera and scale words: wide-angle, wide shot, full body head to toe, figures small in frame, generous empty space above and below. Prohibitions are exactly what the failing users in the forum threads were already doing.
- Set the ratio picker *and* the largest size the UI offers at that ratio, so a reframe is not compounded by a downscale; then compare the output's pixel dimensions against your sketch before judging whether it zoomed.
- If the UI lets you attach two images, put the clean sketch first and a marked-up copy (with frame line and crop corners drawn) second, and refer to them by number in the prompt — plausible and internally consistent, but only one unconfirmed source.

## Sources read

OpenAI official
- https://developers.openai.com/api/docs/guides/image-generation (size constraints, complexity, markup, mask guidance, input_fidelity)
- https://developers.openai.com/cookbook/examples/multimodal/image-gen-models-prompting-guide (markup example, edit patterns, "omit input_fidelity")

OpenAI Developer Community
- https://community.openai.com/t/why-gpt-image-api-crops-original-please-support-flexible-aspect-ratios/1244785 (71 posts read)
- https://community.openai.com/t/how-do-i-get-gpt-to-provide-images-that-are-not-cropped/1279519
- https://community.openai.com/t/gpt-image-1-bias-towards-cropping-with-1024x1024-aspect-ratio/1318395
- https://community.openai.com/t/how-to-stop-odd-cropping-in-image-gen/1230077
- https://community.openai.com/t/gpt-image-api-how-can-i-reliably-edit-only-the-masked-selected-area-while-preserving-everything-else/1389833
- https://community.openai.com/t/gpt-image-2-image-creator-and-editor-app-python-desktop-ui-download-in-latest-j-reply/1370104
- https://community.openai.com/t/gpt-image-1-changing-camera-angle-when-editing-an-image/1360594
- https://community.openai.com/t/mask-is-completely-ignored-in-the-image-edit-api/1350867
- https://community.openai.com/t/gpt-image-1-transparent-backgrounds-with-edit-request… (transparent-background edit thread, checked for size/padding advice)
- https://community.openai.com/t/collection-of-gpt-image-generator-2-0-issues-bugs-and-work-around-tips-check-first-post/1379535 (first post + in-topic searches for crop/zoom)
- https://community.openai.com/t/improving-precision-image-editing-with-gpt-image-2-5-api/1398022
- https://community.openai.com/t/image-generation-high-fidelity-editing/1317649
- https://community.openai.com/t/safety-filter-and-input-fidelity/1327414, …/does-input-fidelity-support-multi-turn-editing/1352586, …/input-fidelity-no-longer-working-with-gpt-image-1-edits-with-mask/1357607, …/input-fidelity/1317640

GitHub
- https://github.com/metadist/synaplan/issues/2404
- https://github.com/mattwestbrooke/ComfyComp_GPTedit/issues/1, /3, /4, /5

Hacker News
- https://news.ycombinator.com/item?id=45219802

## What slowed me down

- Reddit is unreachable from this machine: `reddit.com/search.json`, `api.reddit.com`, `.rss`, `old.reddit.com` (302 to a login wall), and two redlib mirrors (Anubis challenge) all blocked me, and `r.jina.ai` refused with "bad IP reputation". So r/OpenAI, r/ChatGPT, r/StableDiffusion and r/aivideo are cited nowhere above — I only saw their text as snippets inside search results, which I did not count as evidence.
- X/Twitter is login-walled; the only X content I saw was prompt-thread snippets in search results, again not counted.
- Search engines fought back: DDG (html and lite), Ecosia and Mojeek all served CAPTCHAs, Bing ignored my `site:` operators and returned junk, and Brave worked for four curl queries and then demanded a proof-of-work CAPTCHA (it works again inside a real browser, which is how the later searches ran). Google was never usable.
- GitHub issue search is now dominated by AI-generated repos, so phrase searches like `"gpt-image" "zoom in"` returned 339 hits of unrelated garbage; the useful hits came from repo-specific searches and one comment in a design-ops thread.
- The exact symptom is thinly reported. Forum full-text search has no phrase matching worth trusting ("keep the framing", "same framing" returned nothing relevant), and the closest thread to your case — "changing camera angle when editing an image" — has exactly one post and no replies. Most of the real signal sits in one 71-post thread about aspect-ratio cropping from April 2025, which predates GPT-Image-2 and is about gpt-image-1 (now shut down).
