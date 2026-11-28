---
name: aicola-script
description: Turns any story (beat sheet, shot list, prose, screenplay; any language) into input for aicola.cn (可乐AI), the automatic script-to-Seedance video site, then fills it into an aicola project with agent-browser. DeepSeek does the conversion, a checker flags what aicola would mis-parse, a local review page lets the user read and edit every field, and the fill script stops before 保存并拆成分集 (保存并重新拆分 on older projects). Use when the user wants a story run through aicola, an aicola script or settings written, or a pack refilled.
---

# aicola-script

Story in, one aicola project filled out. Nothing that costs credits is ever clicked.

## Pipeline

1. **Convert** (DeepSeek, cheap): `scripts/convert.py` writes a *pack*, one folder with one file per aicola field.
2. **Check** (script, free): `scripts/check.py` runs at the end of convert; rerun after edits.
3. **Lead review** (Claude): read `check.md`, `todo.md` and the script; fix what the worker got wrong (see "What to check").
4. **User review** (page): `scripts/serve.py <pack>` → http://127.0.0.1:8765. The user reads, edits, saves.
5. **Fill** (agent-browser): from the page's "Fill aicola" button, or `scripts/fill.py <pack> --project <name>`. Dry run first.
6. **User** looks at the project on aicola and clicks 保存并拆成分集, then decides on 分步制作 / 一键生成.

## Commands

Run from the film's folder. `S=../_studio/skills/aicola-script/scripts` (or the skill's own path).

```
python3 $S/convert.py --story story/beat-sheet.md story/shot-list.md --style style/style-lock.md --out aicola/<name> [--title 片名] [--note "额外要求"]
python3 $S/check.py aicola/<name>
python3 $S/serve.py aicola/<name>                # review page; run in the background
python3 $S/fill.py aicola/<name> --project <aicola project> --dry-run
python3 $S/fill.py aicola/<name> --project <aicola project>
```

- `--site clone` fills the aicola clone (aicola-global.12dms.com) instead of aicola.cn: its own home URL, renamed values (方案1-脑补, 英语, Seedance 2.5 🌐), 480p through the 视频分辨率 dialog. Map in `SITES` at the top of `fill.py`; evidence in `DayBreak/research/clone/findings.md`. The clone shows 编辑小节润色Skill only after 小节润色 is ticked, and asks 设置未保存 when settings close unsaved.
- `--designs` takes notes on how characters, places and props look (e.g. a film's picks written out); without it the 设定 fields say 未指定 and aicola invents looks. Write such a file first when the film has locked designs.
- `convert.py` makes two worker calls in parallel (script; style + world). `--only script|style` reruns one. It never overwrites `polish.md`, `cast.md` or `settings.json` once they exist, so the user's edits survive a rerun; `script.md`, `title.txt` and the style files are rewritten.
- Worker route: `AICOLA_PROVIDER` / `AICOLA_MODEL` env vars, default `opencode-go` / `deepseek-v4.1-flash`. Logs in `<pack>/logs/`.

## The pack

| File | Goes to (aicola) |
|---|---|
| `title.txt`, `script.md` | 剧本配置 → 标题, 剧本正文 (typed, then plain 保存: stored, not split) |
| `world.md`, `art.md`, `cast.md` | 世界观 / 整体美术 / 全剧人设 dialogs. `cast.md` stays empty by default: the cast lives in the script's `# 角色设定`, which is the path proven to extract well |
| `style-*.md` (5) | 风格切换 自定义: 视频通用提示词, 角色 / 群像角色 / 场景 / 其他对象图片通用提示词. aicola applies 自定义 only when all five are filled |
| `polish.md` | 小节润色Skill: saved once as the workspace template 忠实润色（不加细节） and selected per project. Copied from `prompts/polish.zh.md`. If the template exists, fill.py reuses it as is; edit it on aicola when polish.md changes |
| `settings.json` | 项目设置 dropdowns and switches, by their aicola label |
| `todo.md`, `check.md` | what the worker couldn't tell; what the checker found |
| `fill-state.json`, `fill-screens/` | which project was filled, and screenshots of each step |

## What to check (lead, before the user sees it)

- `check.md` errors: missing header lines, speakers not in the scene, names without a 设定 section. Fix these in `script.md`.
- Names: one name per thing everywhere; place names short Chinese and not alike (aicola merges similar ones).
- Invented content: compare a few scenes against the story. The worker must not add colours, wounds, lines or actions.
- `todo.md`: either answer from the story files, or leave for the user and say so.
- Style files: they come only from the given style source; no story content in them.

Rules are in `references/format-rules.zh.md` (what aicola parses best and why). Settings and evidence: `references/aicola-notes.md`.

## New project

Best made through aicola's 新建项目 wizard (3 steps): name; style 自定义 (it opens the five style prompts right there: each is a button that opens an editor with a textbox "输入…" and 返回列表, then 应用为自定义); then Seedance 2.5, 16:9, 开启消字幕 and 创建并进入项目. Creating a project costs no credits, but do it only when the user asks. Then run `fill.py` (with `--skip settings` if the wizard already set the style; the polish Skill, 视频文本来源, 脑补 and 小节润色模型 still need `fill.py` or the 项目设置 dialog).

## Fill rules (hard)

- Only in a project the user created and named. `fill.py` refuses a project whose script box holds text it didn't put there (`--force` only when the user says so).
- It never clicks 保存并重新拆分 / 保存并拆成分集, 导入剧本自动拆分, 一键生成, 分步制作, 生成视频 or any button containing 生成 / 删除 / 重置. It does click the saves that cost nothing: 保存设置, 应用为自定义, 保存模板, the 世界观 dialog's 保存, and the script's plain 保存.
- Selectors come from labels, not positions. If aicola changes its UI, `fill.py` stops with "not found: …" and a screenshot; fix the label in `fill.py`, or let the user paste that field from the review page (each field has a Copy button).
- Report every `TODO:` line from the fill log to the user: those fields must be set by hand.
