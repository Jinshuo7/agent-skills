#!/usr/bin/env python3
"""Delete old Genspark batch chats: every task-list entry whose chat id appears in a genspark-log.jsonl
file under <folder> (the 'chat' field). Chats not in any log, and pinned chats, are never touched.

Works from one page: opens the task list, deletes matching entries with genspark-batch.py's delete_chat()
(menu > Delete, and the dialog must name that chat), and scrolls the list to load older entries.
No per-chat page loads: opening chat addresses under load gave false "already deleted" answers.

Usage:  genspark-delete-chats.py <folder> [--dry-run] [--max N]
"""
import argparse, glob, importlib.util, json, os, random, re, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("gsb", os.path.join(HERE, "genspark-batch.py"))
g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
LOG = os.path.expanduser("~/.agent-browser-profiles/genspark-deleted-chats.txt")   # record only


def load_ids(folder):
    ids = set()
    for f in glob.glob(os.path.join(folder, "**", "genspark-log.jsonl"), recursive=True):
        for ln in open(f, encoding="utf-8"):
            m = re.search(r"[?&]id=([0-9a-f-]{20,})", ln)
            if m:
                ids.add(m.group(1))
    return ids


def new_tab():
    if g.TAB:
        try: g.TAB.close()
        except Exception: pass
    g.TAB = g.Tab("about:blank"); g.TAB.call("Page.enable")
    g.TAB.call("Emulation.setFocusEmulationEnabled", {"enabled": True})


def open_list(start_url):
    g.ab("open", start_url)
    g.wait_for("!!document.getElementById('agent-history-toggle')", 40, "a page with the task list")
    time.sleep(2)
    if g.js("document.getElementById('agent-history-toggle')?.getAttribute('aria-expanded')") != "true":
        g.click_marked("document.getElementById('agent-history-toggle')", "the task list button")
    g.wait_for("document.querySelectorAll('#agent-history-panel a.project').length>0", 30, "the task list")
    time.sleep(1.5)


LISTED = ("JSON.stringify([...document.querySelectorAll('#agent-history-panel a.project')].map(a=>"
          "[(a.getAttribute('href').match(/id=([0-9a-f-]+)/)||[])[1],!!a.querySelector('.pinned-indicator')]))")
SCROLL = ("(()=>{const a=document.querySelector('#agent-history-panel a.project');let e=a;"
          "while(e&&!(e.scrollHeight>e.clientHeight+5&&/auto|scroll/.test(getComputedStyle(e).overflowY)))e=e.parentElement;"
          "if(!e)return false;e.scrollTop=e.scrollHeight;return true;})()")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder")
    ap.add_argument("--dry-run", action="store_true", help="list the matching entries, delete nothing")
    ap.add_argument("--max", type=int, default=0, help="stop after this many deletions")
    a = ap.parse_args()
    ids = load_ids(a.folder)
    print(f"{len(ids)} chat ids in logs", flush=True)
    new_tab()
    start = "https://www.genspark.ai/agents"   # the All Agents page has the task list button
    deleted, failed, stale, errors = 0, set(), 0, 0
    while True:
        try:
            if not g.js("!!document.getElementById('agent-history-panel')"):
                open_list(start)
            listed = json.loads(g.js(LISTED) or "[]")
            hits = [c for c, pinned in listed if c in ids and not pinned and c not in failed]
            if a.dry_run:
                print(f"matching entries loaded so far: {len(hits)} of {len(listed)}", flush=True)
            if hits and not a.dry_run:
                c = hits[0]
                res = g.delete_chat(f"https://www.genspark.ai/agents?id={c}", verify=False)
                print(f"{c} {res}", flush=True)
                if res.startswith("deleted"):
                    deleted += 1; stale = 0
                    open(LOG, "a").write(c + "\n")
                    if a.max and deleted >= a.max: break
                else:
                    failed.add(c)
                time.sleep(random.uniform(1, 3))
                continue
            before = len(listed)
            if not g.js(SCROLL):
                break
            time.sleep(3)
            if len(json.loads(g.js(LISTED) or "[]")) == before:
                stale += 1
                if stale >= 3: break
        except (g.Stop, RuntimeError, OSError) as e:
            errors += 1
            print(f"error: {e}; reopening the list", flush=True)
            if errors > 15:
                print("too many errors; stopping", flush=True); break
            time.sleep(10)
            new_tab()
            try: open_list(start)
            except Exception as e2: print(f"  reopen failed: {e2}", flush=True)
    listed = json.loads(g.js(LISTED) or "[]") if g.TAB else []
    left = [c for c, p in listed if c in ids and not p]
    print(f"CLEANUP DONE: {deleted} deleted this run; {len(left)} logged chats still in the loaded list ({len(listed)} entries loaded); {len(failed)} failed", flush=True)
    g.TAB.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
