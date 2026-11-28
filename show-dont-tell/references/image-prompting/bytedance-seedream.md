## Research done. Findings below (no files written).

# ByteDance Seedream 5.x (Seedream 5.5 / 5.0) prompting (official sources)

Version note: the newest official prompt guidance is the ModelArk prompt guide, titled in English **"Seedream 4.0-4.5 prompt guide"** but linked from the 5.x tutorial as the prompt guide and titled in Chinese **"Seedream 4.0-5.0 提示词指南"**, covering "Seedream 5.0 lite、4.5 和 4.0". Seedream 5.5 has its own tutorial page (model ID `dola-seedream-5-5-261028`) but no separate prompt guide.

## (a) Prompt structure and order, length, plain vs keyword style

- Prescribed order is subject → action → environment, then aesthetics: "Use coherent natural language to describe the subject + action + environment. If aesthetics matter, include descriptors of style, color, lighting, or composition." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- Prose beats keyword lists, with an explicit official pair: "Recommended: A girl in a lavish dress walking under a parasol along a tree-lined path, in the style of a Monet oil painting." / "Avoid: Girl, umbrella, tree-lined street, oil painting texture." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- State the purpose/type of image up front: "If you have a specific use case, explicitly state the image purpose and type in your prompt." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- Concise beats ornate: "using concise and precise prompts is usually better than repeatedly stacking ornate and complex vocabulary." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- Length ceiling: "Keep text prompts under 600 English words." [https://docs.byteplus.com/en/docs/modelark/image-generation-tutorial]
- The Chinese version gives both ceilings: "文本提示词（prompt）建议不超过300个汉字或600个英文单词。" [https://docs.volcengine.com/docs/ark/image-generation-tutorial?lang=zh]
- For dense/diagrammatic content, order becomes "professional terminology, then visualization format, layout and style": "clearly specify the desired visualization format, layout, and style." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- For multi-turn 5.5 edits, the turn's prompt must state both sides: "state clearly what to change and preserve." [https://docs.byteplus.com/en/docs/modelark/seedream-5-5]

## (b) Reference / input images: how many, how to name them, how to assign roles

- Capacity for 5.x: "Multi-reference-to-image ✓, up to 10 images" for Seedream 5.5, and "Dola Seedream 5.5, Seedream 5.0 pro, and Seedream 5.0 flash support up to 10 images. Seedream 5.0 lite, Seedream 4.5, and Seedream 4.0 support up to 14 images." [https://docs.byteplus.com/en/docs/modelark/seedream-5-5]
- Naming convention in prompts is "Image N": "Replace the subject in Image 1 with the subject from Image 2." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- The Chinese page uses 图一/图二 for the same convention: "将图一的主体替换为图二的主体。" [https://docs.volcengine.com/docs/ark/seedream-4-0-5-0-prompt-guide?lang=zh]
- "Figure 1" also appears in official request examples: `"prompt": "Referring to Figure 1, generate four images with characters wearing sunglasses, riding motorcycles, wearing hats, and holding lollipops"` [https://docs.byteplus.com/en/docs/modelark/image-generation-tutorial]
- One role per image must be stated: "When using this feature, it's recommended to clearly specify what to reference or edit from each image." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- Official worked example of assigning three roles in one prompt: "For example, replace the character in Image 2 with the character from Image 1, and generate the result in the style of Image 3." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- Two-part recipe for a reference image: "Reference Target: Clearly describe the elements to be extracted and retained from the reference image…" plus "Generated Scene Description: Provide detailed information about the desired generated content, including scene, layout, and other specifics." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- Per-image instruction also works in bulk operations: "Extract the sticker elements from Image 1 and Image 2 separately, then place all extracted stickers in one transparent-background image." [https://docs.byteplus.com/en/docs/modelark/seedream-5-5]
- For precise region assignment, image index plus normalized coordinates go inside the prompt: "Use the subject in Image 2 <bbox>118 331 933 871</bbox> to replace the subject in Image 1 <bbox>179 283 796 986</bbox>." Coordinates run 0–999, top-left 0,0 to bottom-right 999,999. [https://docs.byteplus.com/en/docs/modelark/seedream-5-0-pro-editing-guide]
- Input constraint worth knowing when feeding a Blender render: images accept "jpeg, png, webp, bmp, tiff, gif, heic, heif", total pixels "196, 6000×6000", aspect ratio "[1/16, 16]", size "Up to 30 MB". [https://docs.byteplus.com/en/docs/modelark/image-generation-tutorial]

## (c) Keeping a composition or layout from an input image

- The sketch-to-render workflow is officially an *edit*, not a fresh generation: "Edit the image based on the hand-drawn sketch. Add a stack of realistic magazines or art books in the marked area at the lower left… Remove all sketch lines. Keep the composition unchanged. Let the newly added objects blend naturally into the original scene." [https://docs.byteplus.com/en/docs/modelark/seedream-5-0-pro]
- Official sketch guidance, three rules: "Explicitly define key consistencies with the reference, such as ensuring that furniture placement matches the reference image and that the layout follows the prototype." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- Same page: "Provide a clear original image. If the image contains text description, indicate 'Generate based on the text in the image' in the text prompt." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- Floor-plan example shows how hard the lock is stated: "The room layout and furniture placement should exactly match the reference… keep the spatial structure and orientation consistent with the example." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- A depth-ordered walk through the frame is spelled out in that same prompt ("From front to back, the scene should include: sofa & green plants, television, dining table & chairs, and floor-to-ceiling windows"), i.e. layout is pinned by listing elements in spatial order. [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- Scale and subject placement are pinned in prose too: "The generated image should match the size of the original image. Position the figure on the left side of the image." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- Aspect ratio / frame shape is set in words, not a parameter: "Describe the image aspect ratio, shape, or purpose in natural language in the prompt. The model determines the final image size." [https://docs.byteplus.com/en/docs/modelark/seedream-5-0-pro]
- The 5.5 preserve list is explicit and copyable: "Preserve the identity, facial features, gaze, hairstyle, pearl earrings, clothing, pose, blue background, composition, and visual style of the person." [https://docs.byteplus.com/en/docs/modelark/seedream-5-5]
- Mechanically, 5.5 keeps untouched areas pixel-exact: "Preserve unedited regions at the pixel level and eliminate color shifts in those areas" and "targeted training to preserve unedited regions at the pixel level". [https://seed.bytedance.com/en/blog/more-realistic-images-more-stable-editing-across-100-rounds-introducing-seedream-5-5]
- The Chinese 5.5 page frames the same rule as 保持 未编辑区域: "增强多轮编辑中主体特征、构图和未编辑区域的一致性。每轮编辑时，将上一轮生成结果作为输入，并通过提示词明确本轮需要修改和保持不变的内容。" [https://docs.volcengine.com/docs/ark/seedream-5-5?lang=zh]

Not in official sources: any statement about preserving camera parameters (lens, focal length, camera height) or about locking a 3D layout as such; nothing on Blender or on 3D/VFX pipelines.

## (d) Stopping the model from adding or inventing things

- Baseline rule: "Use concise, unambiguous instructions for modifications. Avoid vague pronouns. If other elements should remain unchanged, specify that explicitly." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- Paired example shows the failure mode: "Recommended: Dress the tallest panda in pink Peking Opera costume and headgear, keeping its pose unchanged." / "Avoid: Put that one in pink clothes." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- Negations are written as plain sentences inside the prompt; the sketch workflow relies on one: "Remove all sketch lines." [https://docs.byteplus.com/en/docs/modelark/seedream-5-0-pro]
- The floor-plan prompt carries an explicit do-not list: "Do not include any text or hand-drawn edges from the original sketch." (Chinese: "不需要体现文字和手绘边缘") [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- The Chinese doodle example uses a scope-limited negation: "将房间内红色涂抹位置放入电视，蓝色涂抹位置放入沙发，不改变其他布局" [https://docs.volcengine.com/docs/ark/seedream-4-0-5-0-prompt-guide?lang=zh]
- Per-region freeze is the strongest documented form: "If you want some objects to remain unchanged, you can also include them in bounding boxes and explicitly state 'keep unchanged' or 'do not modify' in the prompt." Example: "…and keep the area Image 1 <bbox>700 120 920 360</bbox> unchanged." [https://docs.byteplus.com/en/docs/modelark/seedream-5-0-pro-editing-guide]
- Ambiguous boxes need a verbal disambiguator, which also limits what the model may pick: "…adding a description in the prompt to specify the target object to edit, such as 'the person on the left', 'the cat wearing a hat', or 'the flower in the foreground'." [https://docs.byteplus.com/en/docs/modelark/seedream-5-0-pro-editing-guide]
- 5.5 multi-turn instructs naming the preserve set every turn: "state clearly what to change and preserve." [https://docs.byteplus.com/en/docs/modelark/seedream-5-5]

Not in official sources: any negative-prompt parameter or negative-prompt syntax. The 5.x prompt surface documented is `prompt` plus `optimize_prompt_options`, with negations only as natural-language sentences inside `prompt`. [https://docs.byteplus.com/en/docs/modelark/image-generation-tutorial]

## (e) Style transfer from a style reference

- Canonical one-liner: "Apply the style of Image 2 to Image 1." (listed as the "Style Transfer" case) [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- Chinese equivalent: "参考图二的风格，对图一进行风格转换。" [https://docs.volcengine.com/docs/ark/seedream-4-0-5-0-prompt-guide?lang=zh]
- Style is passed either by keywords or by a style image: "If a particular style is needed, use precise style keywords or reference images to achieve better results." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- Style-reference example where only the style is borrowed and content is new: "Referencing the linear minimalist style of icons, design 9 application icons for different scenarios… while maintaining a consistent color scheme." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- Style must be named as the retained attribute: "Reference Target: Clearly describe the elements to be extracted and retained from the reference image, such as character design, product material from the reference image." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- Style-lock phrasing in a character reference example: "The overall style should be consistent with the reference image, maintaining a cinematic photographic feel." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- 5.5 carries style across turns as part of the preserve list ("…composition, and visual style of the person") [https://docs.byteplus.com/en/docs/modelark/seedream-5-5]
- 5.5 can also transfer brushwork/material onto new text: "The model can draw on the brushwork, colors, and material effects in a reference image and apply them when rendering specified text." [https://seed.bytedance.com/en/blog/more-realistic-images-more-stable-editing-across-100-rounds-introducing-seedream-5-5]

## (f) Text in images

- Quoting rule: "Use double quotation marks for the text that needs to appear in the generated image." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- Paired example: "Recommended: Generate a poster with the title 'Seedream 4.5'." / "Avoid: Generate a poster titled Seedream 4.5." [https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide]
- 5.5 improves small dense text: "Text rendering also improves significantly, with more accurate rendering of complex character shapes and densely arranged small text." [https://seed.bytedance.com/en/blog/more-realistic-images-more-stable-editing-across-100-rounds-introducing-seedream-5-5]
- Admitted error rates for 5.5: "Seedream 5.5's severe text corruption rate fell to 0.4%, while its minor text corruption rate fell to 1.7%." [https://seed.bytedance.com/en/blog/more-realistic-images-more-stable-editing-across-100-rounds-introducing-seedream-5-5]
- Text plus asset generation in one prompt: a 5.5 demo asks to "Create 'Seedream 5.5'… Use a 16:9 landscape format with a transparent background outside the lettering." [https://seed.bytedance.com/en/seedream5_5]
- Text in a layout can be enumerated with UI details, e.g. "a progress bar (01:24 / 04:32), and a volume icon" inside a transparent-asset prompt. [https://docs.byteplus.com/en/docs/modelark/seedream-5-5]
- If the text must survive as editable text, 5.5 layer decomposition returns OCR: "rich-text OCR results for regular text layers… text content, line-by-line positions, and approximate visual styles." [https://docs.byteplus.com/en/docs/modelark/seedream-5-5]
- OCR font coverage is bounded: "lists the 101 frequently used Chinese fonts and 127 frequently used non-Chinese fonts currently supported for recognition." [https://docs.byteplus.com/en/docs/modelark/ocr-supported-fonts]

## (g) Limits and failure modes the maker admits

- Overlong prompts dilute content: "Very long prompts may scatter the information, causing the model to overlook details and focus only on key points, which can result in missing elements in the generated image." [https://docs.byteplus.com/en/docs/modelark/image-generation-tutorial]
- Speed/quality trade-off: fast prompt optimization "significantly increases generation speed but may reduce image quality." (Seedream 5.0 pro and 4.0; 5.5 is "standard mode (default)" only) [https://docs.byteplus.com/en/docs/modelark/image-generation-tutorial]
- Multi-turn drift is a real, named failure: "small errors can accumulate over successive edits, causing detail loss and image degradation." [https://seed.bytedance.com/en/blog/more-realistic-images-more-stable-editing-across-100-rounds-introducing-seedream-5-5]
- Earlier realism defects acknowledged: 5.5 "reduces excessive gloss and overexposure, and blotchy textures in some images." [https://seed.bytedance.com/en/blog/more-realistic-images-more-stable-editing-across-100-rounds-introducing-seedream-5-5]
- Multi-turn recommendation that constrains input choice: "we recommend using an image without an alpha channel (an RGB image) as the input and setting background to opaque while editing." [https://docs.byteplus.com/en/docs/modelark/seedream-5-5]
- Text-layer OCR limits: "Only regular text layers return OCR results… artistic text, and handwritten text do not return text_recognition." [https://docs.byteplus.com/en/docs/modelark/seedream-5-5]
- Font/style readback is approximate: "similar_font_family is an approximate match and is not guaranteed to equal the original font… returns unknown when recognition is unavailable or confidence is insufficient" and "Style information is approximate. false means the model did not recognize the corresponding style." [https://docs.byteplus.com/en/docs/modelark/seedream-5-5]
- Decomposition planning is left to the model when unspecified: "When a prompt does not specify how to decompose the image, the model plans a result based on max_images and input-image complexity." [https://docs.byteplus.com/en/docs/modelark/seedream-5-5]
- Capability gaps at 5.5: streaming output is unsupported ("Seedream 5.5, Seedream 5.0 pro, and Seedream 5.0 flash do not support this capability"), and layer decomposition accepts one image only. [https://docs.byteplus.com/en/docs/modelark/image-generation-tutorial]
- Outputs are not archived: "Image URL is retained for 24 hours and will be automatically cleared after expiration." [https://docs.byteplus.com/en/docs/modelark/image-generation-tutorial]
- Forward-looking statement: "A Pro version of the Seedream 5.5 series will follow." [https://seed.bytedance.com/en/blog/more-realistic-images-more-stable-editing-across-100-rounds-introducing-seedream-5-5]

## Sources read

- https://seed.bytedance.com/en/ (nav; found the Seedream 5.5 links)
- https://seed.bytedance.com/en/seedream (loaded; marketing shell)
- https://seed.bytedance.com/en/seedream5_5 (showcase page — prompt examples, no rules)
- https://seed.bytedance.com/zh/seedream5_5 (Chinese showcase)
- https://seed.bytedance.com/en/blog/more-realistic-images-more-stable-editing-across-100-rounds-introducing-seedream-5-5
- https://seed.bytedance.com/en/seedream5_0 (SPA shell, no content rendered)
- https://seed.bytedance.com/en/models (status check only)
- https://docs.byteplus.com/en/docs/modelark/seedream-5-5
- https://docs.byteplus.com/en/docs/modelark/seedream-5-0-pro
- https://docs.byteplus.com/en/docs/modelark/seedream-5-0-pro-editing-guide
- https://docs.byteplus.com/en/docs/modelark/image-generation-tutorial
- https://docs.byteplus.com/en/docs/modelark/seedream-4-0-5-0-prompt-guide
- https://docs.byteplus.com/en/docs/modelark/ocr-supported-fonts
- https://docs.byteplus.com/en/docs/modelark/seedream-5-5-supported-fonts (does not exist; redirected to docs home)
- https://docs.byteplus.com/en/docs/ModelArk/1544106 (numeric ID; resolved to a pricing page, not the intended doc)
- https://docs.volcengine.com/docs/ark/seedream-4-0-5-0-prompt-guide?lang=zh (reached via https://www.volcengine.com/docs/ark/seedream-4-0-5-0-prompt-guide?lang=zh)
- https://docs.volcengine.com/docs/ark/seedream-5-5?lang=zh (reached via https://www.volcengine.com/docs/ark/seedream-5-5?lang=zh)
- https://docs.volcengine.com/docs/ark/image-generation-tutorial?lang=zh (reached via https://www.volcengine.com/docs/ark/image-generation-tutorial?lang=zh)
- https://www.volcengine.com/docs/82379/1544106 (numeric ID; resolved to 模型价格 / model pricing)
- https://github.com/ByteDance-Seed (org page)
- https://api.github.com/orgs/ByteDance-Seed/repos (repo list)
- https://api.github.com/search/repositories?q=org:ByteDance-Seed+seedream (0 results)
- https://github.com/ByteDance-Seed/Seedream, /Seedream4, /Seedream-4.0, /seedream (all 404)

## What slowed me down

- Every BytePlus and Volcengine doc page is a JS SPA. Plain `curl` returned only the sidebar or "You need to enable JavaScript to run this app"; the actual prompt text was only reachable through `agent-browser open` + `eval "document.body.innerText"`.
- Numeric doc IDs are unreliable: `docs.byteplus.com/en/docs/ModelArk/1544106` rendered the pricing page, and `www.volcengine.com/docs/82379/1544106` resolved to 模型价格. Slugs are required.
- `www.volcengine.com/docs/...` immediately redirects to `docs.volcengine.com/docs/...`, so the host in my citations differs from the host the task named (same maker, different subdomain).
- The English prompt guide is titled "Seedream 4.0-4.5 prompt guide" while its inbound link text and the Chinese page both say "4.0-5.0", so the version actually covered (and whether 5.5 is covered) had to be read from the page body, not the title.
- There is no Seedream-specific prompt guide for 5.5 — the 5.5 tutorial is capability + API only, so all style/composition rules come from a guide scoped to 4.0/4.5/5.0 lite, plus 5.5-specific remarks scattered in the tutorial and blog.
- `docs.byteplus.com/en/docs/modelark/seedream-5-5-supported-fonts` 404-redirected, and the redirected page kept the generic title "document--ModelArk-Byteplus", so the real OCR-font page had to be found from an in-page link.
- The ByteDance-Seed GitHub org has no Seedream repo and no image-prompting cookbook: repo search returned 0 and the guessed repo paths returned 404. So no GitHub prompting examples exist to cite.
- `seed.bytedance.com` model pages render prompt demos but state no rules, and `/en/seedream5_0` returned an empty SPA shell, so the vendor site contributed only the 5.5 blog and demo prompts.
