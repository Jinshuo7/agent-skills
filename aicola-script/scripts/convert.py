#!/usr/bin/env python3
"""Turn any story into an aicola pack (one folder of fields) with DeepSeek via pi.

  convert.py --story a.md [b.md ...] [--style style.md ...] [--designs looks.md ...] --out <pack dir>
             [--title 片名] [--note "extra instruction"] [--only script|style]

Runs two worker calls in parallel: the screenplay, and the style/world fields.
The polish prompt and default settings are copied from the skill. Then check.py runs.
"""
import argparse, json, os, re, shutil, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fields import SKILL_DIR, STYLE_MARKERS, DEFAULT_SETTINGS, field_path  # noqa: E402

PI = os.path.expanduser("~/.pi/agent/bin/pi")
PROVIDER = os.environ.get("AICOLA_PROVIDER", "opencode-go")
MODEL = os.environ.get("AICOLA_MODEL", "deepseek-v4.1-flash")


def run_pi(workdir: Path, brief: str, log: Path) -> str:
    cmd = [PI, "-p", "--no-session", "--provider", PROVIDER, "--model", MODEL,
           "--tools", "read", brief]
    r = subprocess.run(cmd, cwd=workdir, stdin=subprocess.DEVNULL,
                       capture_output=True, text=True, timeout=1800)
    log.write_text(r.stdout + "\n--- stderr ---\n" + r.stderr, encoding="utf-8")
    if r.returncode != 0 or not r.stdout.strip():
        raise SystemExit(f"worker failed ({r.returncode}); see {log}")
    return r.stdout


def stage(files, workdir: Path, prefix: str):
    names = []
    for i, f in enumerate(files, 1):
        src = Path(f).resolve()
        dst = workdir / f"{prefix}{i}-{src.name}"
        shutil.copy(src, dst)
        names.append(dst.name)
    return names


def strip_fences(s: str) -> str:
    s = s.strip()
    s = re.sub(r"^```[a-z]*\n", "", s)
    s = re.sub(r"\n```$", "", s)
    return s.strip()


def do_script(work, stories, note, pack, title, designs=()):
    brief = (SKILL_DIR / "prompts/convert-script.zh.md").read_text(encoding="utf-8")
    brief = brief.replace("{RULES}", "rules.md").replace("{STORY_FILES}", "、".join(stories))
    extra = ""
    if designs:
        extra += f"- 外观设定资料：{'、'.join(designs)}（只用来写设定字段和五行里的版本名，剧情以故事文件为准）\n"
    if title:
        extra += f"- 片名定为：《{title}》\n"
    if note:
        extra += f"- 额外要求：{note}\n"
    brief = brief.replace("{EXTRA}", extra)
    out = run_pi(work, brief, pack / "logs" / "convert-script.log")
    out = strip_fences(out)
    i = out.find("# 《")
    if i > 0:
        out = out[i:]
    script, _, todo = out.partition("===待确认===")
    field_path(pack, "script").write_text(strip_fences(script) + "\n", encoding="utf-8")
    (pack / "todo.md").write_text("# 待确认（DeepSeek 拿不准的地方）\n\n" + todo.strip() + "\n",
                                  encoding="utf-8")
    m = re.search(r"^# 《(.+?)》", script, re.M)
    t = title or (m.group(1) if m else "")
    field_path(pack, "title").write_text(t + "\n", encoding="utf-8")


def do_style(work, stories, styles, pack):
    brief = (SKILL_DIR / "prompts/convert-style.zh.md").read_text(encoding="utf-8")
    brief = brief.replace("{STYLE_FILES}", "、".join(styles) if styles else "（无）")
    brief = brief.replace("{STORY_FILES}", "、".join(stories))
    out = run_pi(work, brief, pack / "logs" / "convert-style.log")
    parts = re.split(r"^===\s*(.+?)\s*===\s*$", out, flags=re.M)
    got = {}
    for i in range(1, len(parts) - 1, 2):
        key = STYLE_MARKERS.get(parts[i].strip())
        if key:
            got[key] = strip_fences(parts[i + 1])
    missing = [m for m, k in STYLE_MARKERS.items() if k not in got]
    for key, text in got.items():
        field_path(pack, key).write_text(text + "\n", encoding="utf-8")
    if missing:
        print("style: markers missing from worker output:", ", ".join(missing), file=sys.stderr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--story", nargs="+", required=True)
    ap.add_argument("--style", nargs="*", default=[])
    ap.add_argument("--designs", nargs="*", default=[],
                    help="design notes (looks of characters, places, props) used for the 设定 fields")
    ap.add_argument("--out", required=True)
    ap.add_argument("--title")
    ap.add_argument("--note")
    ap.add_argument("--only", choices=["script", "style"])
    a = ap.parse_args()

    pack = Path(a.out).resolve()
    (pack / "logs").mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="aicola-convert-"))
    shutil.copy(SKILL_DIR / "references/format-rules.zh.md", work / "rules.md")
    stories = stage(a.story, work, "story")
    styles = stage(a.style, work, "style")
    designs = stage(a.designs, work, "design")

    # Fixed parts from the skill; never overwrite a file the user already edited.
    pol = field_path(pack, "polish")
    if not pol.exists():
        shutil.copy(SKILL_DIR / "prompts/polish.zh.md", pol)
    for key in ("cast",):
        p = field_path(pack, key)
        if not p.exists():
            p.write_text("", encoding="utf-8")
    sp = pack / "settings.json"
    if not sp.exists():
        sp.write_text(json.dumps(DEFAULT_SETTINGS, ensure_ascii=False, indent=2) + "\n",
                      encoding="utf-8")
    (pack / "sources.json").write_text(json.dumps(
        {"story": [str(Path(s).resolve()) for s in a.story],
         "style": [str(Path(s).resolve()) for s in a.style],
         "designs": [str(Path(s).resolve()) for s in a.designs],
         "model": f"{PROVIDER}/{MODEL}"}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    jobs = []
    with ThreadPoolExecutor(2) as ex:
        if a.only in (None, "script"):
            jobs.append(ex.submit(do_script, work, stories, a.note, pack, a.title, designs))
        if a.only in (None, "style"):
            jobs.append(ex.submit(do_style, work, stories, styles, pack))
        for j in jobs:
            j.result()
    shutil.rmtree(work, ignore_errors=True)

    subprocess.run([sys.executable, str(Path(__file__).with_name("check.py")), str(pack)])
    print(f"pack ready: {pack}")


if __name__ == "__main__":
    main()
