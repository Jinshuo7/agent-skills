#!/usr/bin/env python3
"""Fill one aicola.cn project from a pack, with agent-browser. Saves the script; stops before 保存并拆成分集.

  fill.py <pack dir> --project <name> [--dry-run] [--force] [--session aicola]

What it does, in order:
  1. Opens the named project (one the user created) in the logged-in session.
  2. Refuses if the project's script box already holds text it didn't put there (--force overrides).
  3. 项目设置: applies settings.json, turns on 小节润色 with polish.md, picks 风格切换 自定义
     and fills the five style prompts; then 保存设置 (settings cost no credits).
  4. 世界观 / 整体美术 / 全剧人设 dialogs: fills and saves the non-empty ones.
  5. Types the title and the script into 剧本编辑区, reads them back, clicks plain 保存.
It never clicks 保存并重新拆分, 一键生成, 分步制作, 生成视频 or anything with 生成/删除/重置.
--dry-run opens the project and every dialog, finds every field, types nothing and saves nothing.
"""
import argparse, hashlib, json, re, subprocess, sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fields import STYLE_KEYS, read_field, load_settings  # noqa: E402

HOME = "https://aicola.cn/"
# Per-site differences. "aicola" is the original; "clone" is aicola-global.12dms.com (checked 2026-11-18,
# evidence DayBreak/research/clone/findings.md). values: settings.json value -> the site's option label.
SITES = {
    "aicola": {"home": HOME, "project_url": "/project/", "values": {}, "res_dialog": False, "polish_skill": True},
    "clone": {
        "home": "https://aicola-global.12dms.com/projects?workspaceId=a48f5768-d772-48f0-bd52-366c7fee0965",
        "project_url": "/project/",
        "values": {"方案1": "方案1-脑补", "方案2": "方案2-脑补", "方案2+润色": "方案2-脑补并润色",
                   "英文": "英语", "Seedance 2.5": "Seedance 2.5 🌐", "Seedance 2.5 flash": "Seedance 2.5 flash 🌐",
                   "Seedance 2.0": "Seedance 2.0 🌐"},
        "res_dialog": True,   # 视频分辨率 button -> dialog 选择成片清晰度和生成方式 -> radio "480p 原生" -> 确定
        "polish_skill": True,   # same 选择小节润色Skill模板 dialog; button shows only after 小节润色 is on
    },
}
SITE = SITES["aicola"]
DENY = ("保存并重新拆分", "保存并拆成分集", "导入剧本自动拆分", "一键生成", "分步制作", "生成视频", "生成", "删除", "重置", "归档", "退出")
STYLE_LABELS = {
    "style_video": "视频通用提示词",
    "style_character": "角色图片通用提示词",
    "style_crowd": "群像角色图片通用提示词",
    "style_scene": "场景图片通用提示词",
    "style_other": "其他对象图片通用提示词",
}
NODE = re.compile(r'^(\s*)- (\w+)(?: "((?:[^"\\]|\\.)*)")?(?: \[([^\]]*)\])?(?:: (.*))?$')


class Stop(Exception):
    pass


class Browser:
    def __init__(self, session, dry, shots: Path):
        self.session, self.dry, self.shots, self.n = session, dry, shots, 0

    def ab(self, *args, check=True):
        r = subprocess.run(["agent-browser", "--session", self.session, *args],
                           capture_output=True, text=True, timeout=120)
        if check and r.returncode != 0:
            raise Stop(f"agent-browser {args[0]} failed: {(r.stderr or r.stdout).strip()[:300]}")
        return r.stdout

    def nodes(self):
        out = []
        for line in self.ab("snapshot").splitlines():
            m = NODE.match(line)
            if not m:
                continue
            attrs = m.group(4) or ""
            ref = re.search(r"ref=(e\d+)", attrs)
            out.append({"indent": len(m.group(1)), "role": m.group(2), "name": (m.group(3) or "").replace('\\"', '"'),
                        "attrs": attrs, "ref": ref.group(1) if ref else None, "value": m.group(5) or ""})
        return out

    def find(self, role, name=None, prefix=None, within=None, required=True):
        """First node with role and exact name (or name prefix); optionally inside a dialog named `within`."""
        nodes = self.nodes()
        if within:
            start = next((i for i, n in enumerate(nodes) if n["role"] in ("dialog", "alertdialog") and n["name"].startswith(within)), None)
            if start is None:
                if required:
                    raise Stop(f"dialog '{within}' not open")
                return None
            ind = nodes[start]["indent"]
            sub = []
            for n in nodes[start + 1:]:
                if n["indent"] <= ind:
                    break
                sub.append(n)
            nodes = sub
        for n in nodes:
            if n["role"] == role and n["ref"] and (
                    (name is not None and n["name"] == name) or (prefix is not None and n["name"].startswith(prefix))):
                return n
        if required:
            raise Stop(f"not found: {role} {name or prefix + '…'}" + (f" in '{within}'" if within else ""))
        return None

    def has_dialog(self, prefix):
        """Dialog nodes may carry no ref (clone), so find() can't see them."""
        return any(n["role"] in ("dialog", "alertdialog") and n["name"].startswith(prefix) for n in self.nodes())

    def click(self, node, saving=False):
        if any(d in node["name"] for d in DENY):
            raise Stop(f"refused to click '{node['name']}'")
        if saving and self.dry:
            print(f"  [dry] would click {node['name']}")
            return
        self.ab("click", "@" + node["ref"])
        time.sleep(0.8)

    def fill(self, node, text):
        if self.dry:
            print(f"  [dry] would fill {node['role']} '{node['name'][:30]}' with {len(text)} characters")
            return
        self.ab("fill", "@" + node["ref"], text)
        time.sleep(0.4)

    def value(self, node):
        return self.ab("get", "value", "@" + node["ref"], check=False).rstrip("\n")

    def escape(self):
        self.ab("press", "Escape", check=False)
        time.sleep(0.5)

    def shot(self, label):
        self.shots.mkdir(parents=True, exist_ok=True)
        self.n += 1
        p = self.shots / f"{self.n:02d}-{label}.png"
        self.ab("screenshot", str(p), check=False)
        return p


def sha(s):
    return hashlib.sha256(s.encode("utf-8")).hexdigest()[:16]


def open_project(b: Browser, project):
    print(f"1. opening project '{project}'")
    b.ab("open", SITE["home"])
    time.sleep(2.5)
    b.escape()  # home page ad popup
    enter = b.find("button", "进入项目", required=False)
    if enter:
        b.click(enter)
        time.sleep(3)
    tab = b.find("tab", "项目列表", required=False)
    if tab:
        b.click(tab)
        time.sleep(1.5)
    link = b.find("link", f"打开项目 {project}", required=False)
    if not link:
        names = [n["name"][5:] for n in b.nodes() if n["role"] == "link" and n["name"].startswith("打开项目 ")]
        raise Stop(f"no project named '{project}'. Projects seen: {', '.join(names) or 'none'}")
    b.click(link)
    time.sleep(3)
    url = b.ab("get", "url").strip()
    marker = SITE["project_url"]
    if (marker and marker not in url) or (not marker and url.rstrip("/") == SITE["home"].rstrip("/")):
        raise Stop(f"project didn't open (url {url})")
    for _ in range(3):  # first-visit guide: skip it
        skip = b.find("button", "跳过", required=False)
        if not skip:
            break
        b.ab("click", "@" + skip["ref"])
        time.sleep(0.8)
    b.click(b.find("tab", "剧本配置"))
    return url


def guard(b: Browser, state, force):
    box = b.find("textbox", prefix="建议一次性粘贴完整全剧")
    cur = b.value(box)
    if cur.strip() and sha(cur) != state.get("script_sha") and not force:
        raise Stop("this project's script box already has text this script didn't put there. "
                   "Use an empty project, or pass --force.")
    print(f"2. script box: {'empty' if not cur.strip() else 'holds our last fill'}")


POLISH_TITLE = "忠实润色（不加细节）"


def polish_skill(b: Browser, pack: Path, report):
    """Our polish prompt is a 小节润色Skill template (saved in the workspace, reusable).
    Creates it if missing, else updates nothing, then selects it for this project."""
    polish = read_field(pack, "polish").strip()
    b.click(b.find("button", "编辑小节润色Skill", within="项目设置"))
    time.sleep(1.5)
    dlg = "选择小节润色Skill模板"
    b.click(b.find("tab", prefix="我的自定义", within=dlg))
    time.sleep(1)
    radio = b.find("radio", prefix=POLISH_TITLE, within=dlg, required=False)
    if not radio:
        b.click(b.find("button", "新建自定义", within=dlg))
        time.sleep(1.5)
        b.fill(b.find("textbox", "模板标题", within=dlg), POLISH_TITLE)
        b.fill(b.find("textbox", "模板内容", within=dlg), polish)
        b.click(b.find("button", "保存模板", within=dlg), saving=True)
        time.sleep(2)
        radio = b.find("radio", prefix=POLISH_TITLE, within=dlg, required=not b.dry)
    else:
        print(f"   小节润色Skill '{POLISH_TITLE}' already exists; using it as it is "
              "(edit it on aicola if polish.md changed)")
    if radio:
        b.click(radio, saving=True)
        time.sleep(1.5)
    for _ in range(4):  # Escape alone may only leave the editor (clone); use the dialog's own buttons
        if not b.has_dialog(dlg):
            break
        btn = (b.find("button", "取消", within=dlg, required=False)
               or b.find("button", "关闭模板选择", within=dlg, required=False))
        b.click(btn) if btn else b.escape()
        time.sleep(0.8)
    if not b.dry:  # read back: the Skill button shows the selected template's name under it
        lines = b.ab("snapshot").splitlines()
        i = next((k for k, l in enumerate(lines) if 'button "编辑小节润色Skill"' in l), None)
        if i is None or not any(POLISH_TITLE in l for l in lines[i:i + 5]):
            report.append(f"小节润色Skill: '{POLISH_TITLE}' is not the selected template after the fill "
                          "(clone 2026-11-19 kept 分镜润色 once); pick it in 项目设置 and 保存设置")
    print(f"   小节润色Skill: {POLISH_TITLE} ({len(polish)} characters)")



def set_resolution(b: Browser, want, report):
    """Clone: resolution is a button that opens its own dialog of radios ("480p 原生", "720p 原生", …)."""
    btn = b.find("button", "视频分辨率", within="项目设置", required=False)
    if not btn:
        report.append(f"小节视频分辨率 = {want}: no 视频分辨率 button; set it by hand")
        return
    b.click(btn)
    time.sleep(1)
    dlg = "选择成片清晰度和生成方式"
    radio = b.find("radio", prefix=want, within=dlg, required=False)
    if not radio:
        report.append(f"小节视频分辨率 = {want}: no such option in the dialog; set it by hand")
    elif "checked=true" in radio["attrs"]:
        print(f"   小节视频分辨率: already {radio['name']}")
    elif b.dry:
        print(f"  [dry] would pick {radio['name']}")
    else:
        b.click(radio)
        print(f"   小节视频分辨率: {radio['name']}")
    ok = b.find("button", "确定" if not b.dry else "取消", within=dlg, required=False)
    b.click(ok) if ok else b.escape()
    time.sleep(0.8)


def apply_settings(b: Browser, pack: Path, report):
    print("3. 项目设置")
    settings = load_settings(pack)
    b.click(b.find("button", "项目设置"))
    time.sleep(1.5)
    tab = b.find("tab", "项目设置", within="项目设置", required=False)
    if tab:
        b.click(tab)
        time.sleep(1)
    # 小节润色 first: its 模型 dropdown stays disabled until the switch is on
    polish_on = settings.get("小节润色", "开启") == "开启"
    if polish_on:
        sw = b.find("checkbox", "小节润色", within="项目设置")
        if "checked=true" not in sw["attrs"]:
            # ticked in dry runs too, so the Skill button appears; the dry run closes without 保存设置
            print("  [dry] turning on 小节润色 (discarded on close)" if b.dry else "   小节润色: 开启")
            b.ab("check", "@" + sw["ref"])
            time.sleep(1)
    # plain dropdowns and switches
    for label, want in settings.items():
        if label in ("风格切换", "小节润色"):
            continue
        want = SITE["values"].get(want, want)
        if SITE["res_dialog"] and label == "小节视频分辨率":
            set_resolution(b, want, report)
            continue
        n = b.find("combobox", label, within="项目设置", required=False)
        if n:
            if n["value"].strip() == want:
                print(f"   {label}: already {want}")
            elif b.dry:
                print(f"  [dry] would set {label}: {n['value']} -> {want}")
            else:
                b.ab("select", "@" + n["ref"], want)
                print(f"   {label}: {want}")
            continue
        n = b.find("checkbox", label, within="项目设置", required=False)
        if n:
            on = "checked=true" in n["attrs"]
            want_on = want in ("开启", "on", "true", "是")
            if on != want_on:
                if b.dry:
                    print(f"  [dry] would {'check' if want_on else 'uncheck'} {label}")
                else:
                    b.ab("check" if want_on else "uncheck", "@" + n["ref"])
            print(f"   {label}: {'开启' if want_on else '关闭'}")
            continue
        report.append(f"设置「{label}」= {want}: the script couldn't find this control; set it by hand")

    # 小节润色 + our prompt
    if polish_on:
        if SITE["polish_skill"]:
            polish_skill(b, pack, report)
        else:
            report.append("小节润色: this site has no 小节润色Skill templates; our polish.md was not set "
                          "(see research/clone/findings.md)")

    # 风格切换 = 自定义 -> five prompts
    if settings.get("风格切换") == "自定义":
        tab = b.find("tab", "常用设置", within="项目设置", required=False)
        if tab:
            b.click(tab)
            time.sleep(1)
        radio = b.find("radio", "自定义", within="项目设置")
        b.click(radio)
        time.sleep(1.5)
        dlg = "自定义提示词"
        if not b.has_dialog(dlg):
            report.append("风格切换 自定义: the custom prompt dialog didn't open; fill the 5 style prompts by hand")
        else:
            # The dialog lists five buttons ("<label> *必填 …"); each opens an editor
            # region (outside the dialog node) holding a textbox "输入…" and 返回列表.
            for key in STYLE_KEYS:
                label = STYLE_LABELS[key]
                text = read_field(pack, key).strip()
                opener = b.find("button", prefix=label + " ", within=dlg, required=False)
                if not opener:
                    report.append(f"{label}: not found in the 自定义 dialog; paste it by hand")
                    continue
                b.click(opener)
                time.sleep(0.8)
                box = b.find("textbox", prefix="输入", required=False)
                if not box:
                    report.append(f"{label}: editor didn't open; paste it by hand")
                    continue
                b.fill(box, text)
                if not b.dry and b.value(b.find("textbox", prefix="输入")).strip() != text:
                    report.append(f"{label}: read-back differs; check it")
                print(f"   {label}: {len(text)} characters")
                back = b.find("button", "返回列表", required=False)
                if back:
                    b.click(back)
                    time.sleep(0.6)
            b.shot("custom-style")
            apply = b.find("button", "应用为自定义", within=dlg, required=False)
            if apply:
                b.click(apply, saving=True)
            else:
                report.append("自定义: no 应用为自定义 button found")
            if b.dry:
                b.escape()
    b.shot("settings")
    save = b.find("button", "保存设置", within="项目设置", required=False)
    if save:
        b.click(save, saving=True)
        time.sleep(1.5)
    if b.dry or b.has_dialog("项目设置"):
        close = b.find("button", "关闭", within="项目设置", required=False)
        if close:
            b.click(close)
        else:
            b.escape()
        time.sleep(0.8)
        if b.has_dialog("设置未保存"):  # clone: closing with unsaved changes asks first
            pick = "取消修改并退出" if b.dry else "保存并退出"
            if not b.dry:
                report.append("项目设置 asked 设置未保存 after 保存设置; chose 保存并退出, check the settings")
            # direct click: DENY holds 退出 (log out); these two buttons only leave the settings dialog
            b.ab("click", "@" + b.find("button", pick, within="设置未保存")["ref"])
            time.sleep(1)


def quick_dialogs(b: Browser, pack: Path, report):
    print("4. 世界观 / 整体美术 / 全剧人设")
    for key, label, dialog in (("world", "世界观", "世界观设定"), ("art", "整体美术", "整体美术要求"), ("cast", "全剧人设", "全剧人设")):
        text = read_field(pack, key).strip()
        if not text:
            print(f"   {label}: empty in the pack, skipped")
            continue
        btn = b.find("button", prefix=label + "，")
        b.click(btn)
        time.sleep(1)
        if b.has_dialog("无法修改"):
            report.append(f"{label}: aicola says it can't be changed any more (objects already extracted)")
            b.escape()
            continue
        box = b.find("textbox", prefix="", within=dialog, required=False)
        if not box:
            report.append(f"{label}: no text box in the dialog; paste {key}.md by hand")
            b.escape()
            continue
        b.fill(box, text)
        print(f"   {label}: {len(text)} characters")
        save = b.find("button", "保存", within=dialog)
        b.click(save, saving=True)
        if b.dry:
            cancel = b.find("button", "取消", within=dialog, required=False)
            b.click(cancel) if cancel else b.escape()
        time.sleep(1)


def fill_script(b: Browser, pack: Path, report):
    print("5. 剧本编辑区")
    title = read_field(pack, "title").strip()
    script = read_field(pack, "script")
    tbox = b.find("textbox", "标题")
    b.fill(tbox, title)
    box = b.find("textbox", prefix="建议一次性粘贴完整全剧")
    b.fill(box, script)
    if not b.dry:
        got = b.value(b.find("textbox", prefix="建议一次性粘贴完整全剧"))
        if got.strip() != script.strip():
            report.append(f"script box reads back {len(got)} characters, pack has {len(script)}: check it on the page")
        else:
            print(f"   script: {len(script)} characters, read back OK")
    # Plain 保存 stores the text without splitting (no credits). Without it the text
    # lives only in the automation browser and the user can't see it.
    b.click(b.find("button", "保存"), saving=True)
    time.sleep(2.5)
    b.shot("script")
    return sha(script)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pack")
    ap.add_argument("--project", required=True)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--session", default="aicola")
    ap.add_argument("--skip", nargs="*", default=[], choices=["settings", "quick", "script"])
    ap.add_argument("--site", default="aicola", choices=sorted(SITES))
    a = ap.parse_args()
    global SITE
    SITE = SITES[a.site]
    pack = Path(a.pack).resolve()
    sp = pack / "fill-state.json"
    state = json.loads(sp.read_text(encoding="utf-8")) if sp.exists() else {}
    if state.get("project") not in (None, a.project):
        state = {}
    b = Browser(a.session, a.dry_run, pack / "fill-screens")
    report = []
    try:
        url = open_project(b, a.project)
        guard(b, state, a.force)
        if "settings" not in a.skip:
            apply_settings(b, pack, report)
        if "quick" not in a.skip:
            quick_dialogs(b, pack, report)
        script_sha = fill_script(b, pack, report) if "script" not in a.skip else state.get("script_sha")
    except Stop as e:
        b.shot("stopped")
        print(f"\nSTOPPED: {e}")
        sys.exit(1)
    if not a.dry_run:
        sp.write_text(json.dumps({"project": a.project, "url": url, "script_sha": script_sha,
                                  "filled_at": time.strftime("%Y-%m-%d %H:%M")}, ensure_ascii=False, indent=2),
                      encoding="utf-8")
    print("\nDone." + (" (dry run: nothing typed or saved)" if a.dry_run else ""))
    for r in report:
        print("  TODO:", r)
    if not a.dry_run:
        print(f"\nNext, on aicola ({url}): read the script, then click 保存并拆成分集 yourself.")


if __name__ == "__main__":
    main()
