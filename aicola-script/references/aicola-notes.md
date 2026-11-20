# aicola.cn notes (generic, no story content)

From a read-only study on 2026-11-16 (evidence: `DayBreak/research/aicola/`). Untested points are marked.


**Pipeline:** script → split (DeepSeek V4.1 Flash) → object extraction with versions (DeepSeek V4 Pro) → object images (GPT Image 2 / Seedream 5.0 Pro) and voices (Seed Audio) → sections ≤30 s, polished by Doubao Seed 2.1 Pro → one Seedance 2.5 call per section (multimodal reference mode, audio on, subtitles erased). One-click mode runs these steps as a task graph.

**The Seedance prompt, in order:**
1. A reference map: "图片N为角色X[版本]的多角度视图，左侧脸部特写=面部参考，右侧全身=妆造参考，身高…", props as "X[版本]是图片N", voices as "X的音色是音频N".
2. `-剧本内容开始：` + the polished section text + `-剧本内容结束。`
3. A style block from the chosen preset: 【视频风格】【剧情节奏】【画面一致性】【人物表现】【角色限制】【镜头语言】【画面限制】.
4. A fixed rule: phone or letter reading is shot over the shoulder or as shot-reverse-shot.

**Polished section syntax:** `{描述说明：…}`, `<名字[版本]登场>` / `<…离场>`, one action per line in （）, dialogue as `名字[版本](语气，情绪：…)："台词"`. Names must match the object list exactly, because they are how the reference images get attached.

**Input format the site parses best:**
- Structure: `# 《Title》` → `# 全剧梗概` → `# 角色设定` / `# 群体设定` / `# 机械设定` → `# 剧本` → `# 第1集` → `## 1-1场`.
- Each scene starts with header lines: `**场景：地点，时间，内/外。**`, `**人物：…**`, `**群体人物：…**`, `**声音角色：…**`, `**其他对象：…**`.
- The header lines and the setting sections feed object extraction only. They are dropped from the video text.

**Splitting:**
- A scene is not a section. Long scenes are cut at a beat boundary (after a line or a finished action), and a section can span two scenes.
- A full 30 s section holds about 600-800 characters.
- The exact thresholds are unknown.

**Objects:**
- There are 3 types: character, scene, other.
- Each type has fixed description fields:
  - Character (13): 种族, 地区, 年龄, 性别, 颜值, 身份, 年代, 长相, 妆容, 身材, 穿着, 发型, 配饰.
  - Scene: 宏观结构 / 近景 / 远景 / 光线 / 天气 / 氛围.
  - Prop: 种类 / 尺寸 / 结构 / 年代与风格.
- Empty fields get invented values unless 脑补 (inferring looks) is set to 不脑补.
- Crowds become one `…群像` character. Voice-only and non-human beings become characters with "无" in their fields.
- Place names are shortened, translated to Chinese and sometimes merged.
- Versions were split reliably only for scenes, by time labels in the scene header. State changes to props and characters were not split. Explicit version names are untested.

**What the polisher does wrong:**
- It adds sensory detail and emotion tags, makes images more intense, and invents colours and distances.
- It copies these straight into the video text: notes to the audience, references to other scenes, "don't…" lines, undefined abstract terms.
- It drops time and flashback labels unless they are also in 描述说明.

**Settings (项目设置 → 全部):**

| Setting | Options |
|---|---|
| 风格切换 | 10 presets (真人实拍, 3D漫剧, 3D乙游, genre live-action variants) or 自定义. There is no 2D anime preset. |
| 自定义 fields | 视频通用提示词 (replaces the style block), 角色图片, 群像角色图片, 场景图片, 其他对象图片 |
| 视频文本来源 | 手动文本 / 可乐润色文本 / 小节润色文本 (polish with a user prompt) |
| 脑补角色外表描述 | 不脑补 / 方案1 / 方案2 / 方案2+润色 |
| Video | Seedance 2.5 / 2.5 flash / 2.0 / Fast / Mini; ratio; 720p; MP4 or MOV; 成片语种; 消字幕 |
| Images | Model and resolution per type; character layout 完整正背面 or 无头妆造; scene layout 上下 or 四分格 |

You can upload your own image for any object version ("从本地上传"). It must follow the site's character layout: face on the left, full body on the right.

## Open questions (untested, each needs a paid run)

- Do explicit version names in the header (e.g. `人物：甲（面罩）`) create versions?
- Are uploaded images accepted as-is?
- Does English dialogue survive with 成片语种 = English?
- What does a section cost at 720p? (About 300 credits per 30 s section at 480p.)

## Limits from the site's code

- 世界观, 整体美术, 全剧人设 and each style prompt: 10,000 characters. 小节润色 prompt: 50,000.
- Script upload: DOC/DOCX/TXT up to 20 MB; paste works the same.
- 自定义 style is applied only when all five prompts are filled (button tooltip: 请先填写全部五项提示词).
- 全剧人设 locks once objects are extracted (dialog 无法修改全剧人设).

## 消除字幕: usually not needed (tested 2026-11-20, DayBreak-Draft5 on the clone)
With 无字幕 in the video style prompt, 成片语种 英语 and 翻译台词 / 翻译画面文字 off, Seedance 2.5 burned no captions into any of 21 原片 (visual check of 4 dialogue/silent clips; pixel diff 原片 vs 消字幕1 was re-encode noise only in all 21). The removal pass only adds time. Set 消除字幕 = 关闭 for packs like this; leave it on if translations are on or the style prompt allows text. The 原片 link is the `videoSourceUrl` field of `/api/workspaces/<project>/scenes/<id>/shots`.
