#!/usr/bin/env python3
"""suit-up helper. Standard library only.

  suitup.py where                         show the configured skill libraries
  suitup.py set-library <folder>...       save the skill libraries
  suitup.py list                          one line per library skill
  suitup.py status <project>              what is in the project's skills folder
  suitup.py link <project> <skill>...     link skills into the project (dry run)
  suitup.py unlink <project> <name>...    remove kit links (dry run); --all for every kit link

link and unlink change nothing unless --apply is given.
A "kit link" is a symlink in the project's skills folder that points into a library.
"""
import argparse
import os
import re
import sys

CONFIG = os.path.join(
    os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
    "suit-up", "libraries")
CANDIDATES = ["~/.skills-manager/skills", "~/skills", "~/.skills", "~/skills-library"]


def die(msg, code=2):
    print(msg, file=sys.stderr)
    sys.exit(code)


def norm(path):
    return os.path.realpath(os.path.expanduser(path))


def has_skills(folder):
    try:
        return any(os.path.isfile(os.path.join(folder, e, "SKILL.md")) for e in os.listdir(folder))
    except OSError:
        return False


def libraries():
    libs = []
    if os.environ.get("SUIT_UP_LIBRARY"):
        libs = os.environ["SUIT_UP_LIBRARY"].split(os.pathsep)
    elif os.path.isfile(CONFIG):
        with open(CONFIG) as f:
            libs = [l.strip() for l in f if l.strip() and not l.startswith("#")]
    libs = [norm(l) for l in libs]
    if not libs:
        found = [norm(c) for c in CANDIDATES if has_skills(norm(c))]
        hint = "\nFolders that look like a library:\n  " + "\n  ".join(found) if found else ""
        die("No skill library configured. Ask the user which folder holds their skills, "
            "then run: suitup.py set-library <folder>" + hint)
    missing = [l for l in libs if not os.path.isdir(l)]
    if missing:
        die("Configured library folder not found: " + ", ".join(missing))
    return libs


def frontmatter(skill_md):
    try:
        with open(skill_md, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return {}
    if not text.startswith("---"):
        return {}
    lines = text.split("\n---", 1)[0].splitlines()[1:]
    out, i = {}, 0
    while i < len(lines):
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", lines[i])
        i += 1
        if not m:
            continue
        key, val = m.group(1), m.group(2).strip()
        if val in ("", ">", "|", ">-", "|-", ">+", "|+"):
            block = []
            while i < len(lines) and (lines[i].startswith((" ", "\t")) or not lines[i].strip()):
                block.append(lines[i].strip())
                i += 1
            val = " ".join(b for b in block if b)
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        out[key] = val
    return out


def skills(libs):
    found = []
    for lib in libs:
        for entry in sorted(os.listdir(lib)):
            folder = os.path.join(lib, entry)
            md = os.path.join(folder, "SKILL.md")
            if entry.startswith(".") or not os.path.isfile(md):
                continue
            fm = frontmatter(md)
            found.append({
                "folder": entry,
                "name": fm.get("name") or entry,
                "path": folder,
                "description": " ".join((fm.get("description") or "").split()),
                "manual": (fm.get("disable-model-invocation") or "").lower() == "true",
            })
    return found


def project_dir(project, sub):
    project = os.path.abspath(os.path.expanduser(project))
    if not os.path.isdir(project):
        die("Project folder not found: " + project)
    return project, os.path.join(project, sub)


def link_target(path):
    """Absolute target of a symlink, without requiring it to exist."""
    target = os.readlink(path)
    if not os.path.isabs(target):
        target = os.path.join(os.path.dirname(path), target)
    return os.path.realpath(target)


def in_library(target, libs):
    return any(target.startswith(lib + os.sep) for lib in libs)


def entries(skills_dir, libs):
    rows = []
    if not os.path.isdir(skills_dir):
        return rows
    for entry in sorted(os.listdir(skills_dir)):
        path = os.path.join(skills_dir, entry)
        if os.path.islink(path):
            target = link_target(path)
            if in_library(target, libs):
                kind = "kit" if os.path.isfile(os.path.join(target, "SKILL.md")) else "kit-broken"
            else:
                kind = "foreign-link"
            rows.append((entry, kind, target))
        else:
            rows.append((entry, "foreign", ""))
    return rows


def cmd_where(args):
    libs = libraries()
    source = "SUIT_UP_LIBRARY" if os.environ.get("SUIT_UP_LIBRARY") else CONFIG
    print("source: " + source)
    for lib in libs:
        print("library: " + lib)


def cmd_set_library(args):
    libs = [norm(l) for l in args.folders]
    bad = [l for l in libs if not has_skills(l)]
    if bad:
        die("No <skill>/SKILL.md found in: " + ", ".join(bad))
    os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
    with open(CONFIG, "w") as f:
        f.write("\n".join(libs) + "\n")
    print("saved to " + CONFIG)
    for lib in libs:
        print("library: " + lib)


def cmd_list(args):
    for s in skills(libraries()):
        name = s["name"] + (" (manual)" if s["manual"] else "")
        print(" | ".join([name, s["path"], s["description"][:args.width]]))


def cmd_status(args):
    libs = libraries()
    project, skills_dir = project_dir(args.project, args.dir)
    rows = entries(skills_dir, libs)
    print("skills folder: " + skills_dir + ("" if os.path.isdir(skills_dir) else " (does not exist)"))
    for entry, kind, target in rows:
        print(" | ".join([kind, entry, target]))
    if not rows:
        print("(empty)")


def resolve(ref, catalog):
    if os.sep in ref:
        path = norm(ref)
        hits = [s for s in catalog if s["path"] == path]
    else:
        hits = [s for s in catalog if ref in (s["folder"], s["name"])]
    if not hits:
        die("Skill not found in the library: " + ref)
    if len({s["path"] for s in hits}) > 1:
        die("Ambiguous skill '" + ref + "'; give the full path. Matches:\n  "
            + "\n  ".join(s["path"] for s in hits))
    return hits[0]


def cmd_link(args):
    libs = libraries()
    catalog = skills(libs)
    project, skills_dir = project_dir(args.project, args.dir)
    plan, clashes = [], []
    for ref in args.skills:
        s = resolve(ref, catalog)
        dest = os.path.join(skills_dir, s["folder"])
        if os.path.islink(dest) and link_target(dest) == s["path"]:
            plan.append(("already-linked", dest, s["path"]))
        elif os.path.lexists(dest):
            clashes.append(dest)
        else:
            plan.append(("link", dest, s["path"]))
    if clashes:
        die("Nothing changed. These names already exist in the project and are not this kit's links; "
            "ask the user:\n  " + "\n  ".join(clashes), 3)
    for action, dest, target in plan:
        if action == "link" and args.apply:
            os.makedirs(skills_dir, exist_ok=True)
            os.symlink(target, dest)
            action = "linked"
        print(" | ".join([action, dest, target]))
    if not args.apply:
        print("dry run: nothing changed. Add --apply to do it.")


def cmd_unlink(args):
    libs = libraries()
    project, skills_dir = project_dir(args.project, args.dir)
    rows = {e: (kind, target) for e, kind, target in entries(skills_dir, libs)}
    if args.all == bool(args.names):
        die("Give skill names, or --all (not both).")
    names = [e for e, (kind, _) in rows.items() if kind.startswith("kit")] if args.all else args.names
    refused = [n for n in names if n not in rows or not rows[n][0].startswith("kit")]
    if refused:
        die("Nothing changed. Not kit links (missing, or not symlinks into the library):\n  "
            + "\n  ".join(refused), 3)
    for n in names:
        path = os.path.join(skills_dir, n)
        if args.apply:
            os.unlink(path)
        print(" | ".join(["unlinked" if args.apply else "unlink", path, rows[n][1]]))
    if not names:
        print("no kit links to remove")
    if not args.apply:
        print("dry run: nothing changed. Add --apply to do it.")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("where").set_defaults(fn=cmd_where)
    sp = sub.add_parser("set-library"); sp.add_argument("folders", nargs="+"); sp.set_defaults(fn=cmd_set_library)
    sp = sub.add_parser("list"); sp.add_argument("--width", type=int, default=200); sp.set_defaults(fn=cmd_list)
    for name, fn in (("status", cmd_status), ("link", cmd_link), ("unlink", cmd_unlink)):
        sp = sub.add_parser(name)
        sp.add_argument("project")
        sp.add_argument("--dir", default=os.path.join(".claude", "skills"),
                        help="skills folder inside the project (default: .claude/skills)")
        if name == "link":
            sp.add_argument("skills", nargs="+")
        if name == "unlink":
            sp.add_argument("names", nargs="*")
            sp.add_argument("--all", action="store_true")
        if name != "status":
            sp.add_argument("--apply", action="store_true")
        sp.set_defaults(fn=fn)
    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
