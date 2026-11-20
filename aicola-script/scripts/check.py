#!/usr/bin/env python3
"""Lint an aicola pack against references/format-rules.zh.md.

  check.py <pack dir>      writes <pack>/check.json and check.md, prints a summary

Levels: error = aicola will likely mis-parse it; warn = worth a look.
"""
import json, re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fields import FIELDS, STYLE_KEYS, read_field  # noqa: E402

SETTING_SECTIONS = ("角色设定", "群体设定", "生物设定", "机械设定", "其他对象设定")
HEADERS = ["场景", "人物", "群体人物", "声音角色", "其他对象"]
SPLIT = re.compile(r"[，、,;；]")
VERSION = re.compile(r"[（(][^）)]*[）)]")
DIALOGUE = re.compile(r'^(?P<who>[^（(\s"“：:{<]+?)\s*[（(](?P<tone>[^）)]*)[）)]\s*[:：]\s*["“].*')
BANNED = [
    (re.compile(r"\bshot\s*\d", re.I), "shot number"),
    (re.compile(r"镜号"), "shot number"),
    (re.compile(r"(?<![\w.])\d+(\.\d+)?\s*(s|秒)(?![a-z])"), "seconds / timing"),
    (re.compile(r"\|"), "table"),
    (re.compile(r"观众|读者"), "note to the audience"),
    (re.compile(r"不要|禁止|切勿|避免"), "negative instruction (polisher copies it into the video)"),
    (re.compile(r"\bCUT TO\b|\bFADE\b|\bINT\.|\bEXT\.", re.I), "screenplay transition"),
    (re.compile(r"[（(]注[:：]"), "note"),
    (re.compile(r"\d+-\d+场"), "reference to another scene"),
    (re.compile(r"形成对比|呼应|象征|暗示"), "meta / abstract wording"),
]


def outside_quotes(line: str) -> str:
    return re.sub(r'["“][^"”]*["”]', "", line)


def names_of(value: str):
    value = value.strip().rstrip("。.").strip()
    if not value or value in ("无", "无。"):
        return []
    out = []
    for part in SPLIT.split(value):
        part = part.strip().rstrip("。")
        if not part or part == "无":
            continue
        out.append((VERSION.sub("", part).strip(), part))
    return out


def parse(script: str):
    known, section = {}, None
    scenes, cur = [], None
    for n, raw in enumerate(script.splitlines(), 1):
        line = raw.strip()
        m = re.match(r"^#\s+(.+)$", line)
        if m:
            title = m.group(1).strip()
            section = title if title in SETTING_SECTIONS else ("剧本" if title in ("剧本",) or title.startswith("第") else None)
            continue
        m = re.match(r"^##\s+(.+)$", line)
        if m:
            h = m.group(1).strip()
            sm = re.match(r"^(\d+)-(\d+)场", h)
            if sm:
                cur = {"id": f"{sm.group(1)}-{sm.group(2)}", "line": n, "headers": {}, "body": []}
                scenes.append(cur)
                section = "剧本"
            elif section in SETTING_SECTIONS:
                known[VERSION.sub("", h).strip()] = section
            continue
        if cur is not None and section == "剧本":
            hm = re.match(r"^\*\*(场景|人物|群体人物|声音角色|其他对象)[:：](.*?)\*\*$", line)
            if hm:
                cur["headers"][hm.group(1)] = hm.group(2)
            elif line:
                cur["body"].append((n, line))
    return known, scenes


def check(pack: Path):
    issues = []
    add = lambda lvl, where, msg: issues.append({"level": lvl, "where": where, "msg": msg})

    for key, fname, label, limit in FIELDS:
        text = read_field(pack, key)
        if limit and len(text) > limit:
            add("error", fname, f"{len(text)} characters, aicola keeps only {limit}")
    for key in STYLE_KEYS:
        t = read_field(pack, key).strip()
        if not t or "未提供画风" in t:
            add("error", key, "empty: aicola applies 自定义 only when all five style prompts are filled")
    if "【画面限制】" not in read_field(pack, "style_video"):
        add("warn", "style_video", "no 【画面限制】 block (无字幕，无文字，无Logo，无水印，无BGM)")
    if not read_field(pack, "title").strip():
        add("error", "title.txt", "empty title")

    script = read_field(pack, "script")
    if not script.strip():
        add("error", "script.md", "empty script")
        return issues
    for need in ("# 《", "# 全剧梗概", "# 角色设定", "# 剧本", "# 第1集"):
        if need not in script:
            add("error", "script.md", f"missing `{need}`")

    known, scenes = parse(script)
    if not scenes:
        add("error", "script.md", "no scenes found (`## 1-1场`)")
    places = {}
    for sc in scenes:
        where = f"{sc['id']}场 (line {sc['line']})"
        for h in HEADERS:
            if h not in sc["headers"]:
                add("error", where, f"missing header line **{h}：…**")
        present = set()
        for h in ("人物", "群体人物", "声音角色"):
            for base, full in names_of(sc["headers"].get(h, "")):
                present.add(base)
                if base not in known:
                    add("error", where, f"{h} `{base}` has no section in the 设定 parts")
                if h == "群体人物" and not base.endswith("群像"):
                    add("warn", where, f"crowd `{base}` should end in 群像")
        place = sc["headers"].get("场景", "")
        pname = SPLIT.split(place)[0].strip() if place else ""
        if pname:
            places.setdefault(pname, []).append(sc["id"])
        if not any(l.startswith("{描述说明") for _, l in sc["body"]):
            add("warn", where, "no {描述说明：…} line")
        size = sum(len(l) for _, l in sc["body"])
        if size > 900:
            add("warn", where, f"{size} characters: long, aicola will cut it into several sections; consider splitting at a turn")
        elif size < 120:
            add("warn", where, f"only {size} characters")
        for n, l in sc["body"]:
            if l.startswith("{描述说明"):
                pass
            elif l.startswith("（") or l.startswith("("):
                if not (l.endswith("）") or l.endswith(")")):
                    add("warn", f"line {n}", "action line doesn't close its bracket")
            else:
                dm = DIALOGUE.match(l)
                if dm:
                    who = VERSION.sub("", dm.group("who")).strip()
                    if who not in present:
                        add("error", f"line {n}", f"speaker `{who}` not in this scene's 人物/群体人物/声音角色")
                elif l != "---":
                    add("warn", f"line {n}", f"not an action, line or 描述说明: {l[:40]}")
            body = outside_quotes(l)
            for rx, why in BANNED:
                if rx.search(body):
                    add("warn", f"line {n}", f"{why}: {l[:50]}")
    # near-duplicate place names merge on aicola
    pl = sorted(places)
    for i, a in enumerate(pl):
        for b in pl[i + 1:]:
            if a in b or b in a:
                add("warn", "places", f"`{a}` and `{b}` look alike; aicola may merge them")
    return issues


def main():
    pack = Path(sys.argv[1]).resolve()
    issues = check(pack)
    (pack / "check.json").write_text(json.dumps(issues, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = ["# Check", ""]
    for lvl in ("error", "warn"):
        rows = [i for i in issues if i["level"] == lvl]
        lines.append(f"## {lvl} ({len(rows)})")
        lines += [f"- {i['where']}: {i['msg']}" for i in rows] or ["- none"]
        lines.append("")
    (pack / "check.md").write_text("\n".join(lines), encoding="utf-8")
    e = sum(i["level"] == "error" for i in issues)
    w = len(issues) - e
    print(f"check: {e} errors, {w} warnings -> {pack / 'check.md'}")


if __name__ == "__main__":
    main()
