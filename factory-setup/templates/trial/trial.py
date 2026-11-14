#!/usr/bin/env python3
"""trial.py - short model trial in a throwaway checkout.

  trial.py worker '<slot command>' [label] | trial.py review '<slot command>' [label]
"""
import os, re, shutil, signal, subprocess, sys, tempfile, time

SRC = os.path.dirname(os.path.abspath(__file__))
LIMIT = 900
ID = {"GIT_AUTHOR_NAME": "belt-trial", "GIT_AUTHOR_EMAIL": "belt-trial@example.invalid",
      "GIT_COMMITTER_NAME": "belt-trial", "GIT_COMMITTER_EMAIL": "belt-trial@example.invalid"}
WORKER_PROMPT = "Implement the functions in grocery.py so every test in test_grocery.py passes. Do not edit test_grocery.py. Keep the code simple. Run python3 -m unittest -q to check before you finish. Reply with one line saying whether all tests pass."
REVIEW_PROMPT = """Review this diff of the checkout in the current folder (head {head}); you may read other files for context.
This PR is meant to close a GitHub issue. Look for correctness bugs, safety problems and missing tests.
Be concrete and terse.
List findings one per line using exactly the prefixes "P1: " (must fix before merge) or "P2: " (minor),
at most 12 finding lines in total. Then finish with a last line that is exactly:
VERDICT: PASS
or
VERDICT: FIX
Use VERDICT: FIX if and only if there is at least one P1 finding.
The diff:
```
{diff}
```
"""
SCORER = """import importlib, sys, unittest
class R(unittest.TestResult):
    def addSuccess(self, t):
        self.p = getattr(self, "p", 0) + 1; super().addSuccess(t)
s = unittest.defaultTestLoader.loadTestsFromModule(importlib.import_module(sys.argv[1]))
r = R(); s.run(r); print(getattr(r, "p", 0), s.countTestCases())
"""

for _sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(_sig, lambda *_: sys.exit(1))

def die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)
def git(work, *args):
    p = subprocess.run(["git", "-C", work, *args], capture_output=True, text=True, env=dict(os.environ, **ID))
    if p.returncode: die("git %s failed" % args[0])
    return p.stdout.strip()
def reject(rc, timed_out, *extra):
    reasons = (["timed out after %ds" % LIMIT] if timed_out else
               ["slot command failed (exit %d)" % rc] if rc else []) + [e for e in extra if e]
    if reasons:
        print("REJECTED: " + "; ".join(reasons))
def run_slot(work, base, tag, prompt, slot):
    pf, out, so = (os.path.join(base, tag + s) for s in ("-prompt.txt", "-answer.out", "-stdout.log"))
    with open(pf, "w") as handle: handle.write(prompt if prompt.endswith("\n") else prompt + "\n")
    open(out, "w").close()
    start, timed_out = time.time(), False
    with open(so, "w") as stdout:
        proc = subprocess.Popen(["bash", "-c", slot], cwd=work, stdin=subprocess.DEVNULL,
                                stdout=stdout, stderr=subprocess.DEVNULL, start_new_session=True,
                                env=dict(os.environ, BELT_PROMPT_FILE=pf, BELT_OUT_FILE=out))
        try:
            proc.wait(timeout=LIMIT)
        except subprocess.TimeoutExpired:
            timed_out = True
            for sig in (signal.SIGTERM, signal.SIGKILL):
                try: os.killpg(proc.pid, sig); proc.wait(timeout=5); break
                except (OSError, subprocess.TimeoutExpired): pass
    rc = proc.returncode if proc.returncode is not None else -signal.SIGKILL
    rc = rc + 128 if rc < 0 else rc
    answer = next((open(f, errors="replace").read() for f in (out, so) if os.path.getsize(f)), "")
    return rc, int(time.time() - start), timed_out, answer
def score(work, module):
    try:
        found = re.findall(r"(?m)^(\d+) (\d+)$", subprocess.run(
            [sys.executable, "-c", SCORER, module], cwd=work,
            capture_output=True, text=True, timeout=180).stdout)
        if found:
            return int(found[-1][0]), int(found[-1][1])
    except subprocess.TimeoutExpired: pass
    source = os.path.join(work, module + ".py")
    if not os.path.isfile(source): return 0, 0
    return 0, len(re.findall(r"(?m)^\s*def\s+(test\w*)\s*\(", open(source, errors="replace").read()))
def worker(base, slot, label):
    work = os.path.join(base, "work"); os.mkdir(work)
    for name in ("grocery.py", "test_grocery.py"):
        shutil.copy(os.path.join(SRC, "worker", name), work)
    for args in (("init", "-q"), ("add", "--", "grocery.py", "test_grocery.py"),
                 ("commit", "-q", "-m", "initial")):
        git(work, *args)
    test_path, grocery = os.path.join(work, "test_grocery.py"), os.path.join(work, "grocery.py")
    tests = open(test_path, "rb").read()

    rc, secs, timed_out, _ = run_slot(work, base, "worker", WORKER_PROMPT, slot)
    visible = score(work, "test_grocery")
    shutil.copy(os.path.join(SRC, "worker", "hidden_test_grocery.py"), work)
    hidden = score(work, "hidden_test_grocery")
    os.remove(os.path.join(work, "hidden_test_grocery.py"))
    untouched = os.path.isfile(test_path) and open(test_path, "rb").read() == tests
    lines = len(open(grocery, errors="replace").read().splitlines()) if os.path.isfile(grocery) else 0

    print("WORKER %s visible=%d/%d hidden=%d/%d tests_untouched=%s secs=%d exit=%d lines=%d"
          % (label, *visible, *hidden, "yes" if untouched else "no", secs, rc, lines))
    reject(rc, timed_out, "" if untouched else "tests were changed")
def review(base, slot, label):
    work = os.path.join(base, "work"); os.mkdir(work)
    git(work, "init", "-q")
    git(work, "symbolic-ref", "HEAD", "refs/heads/main")
    for name in ("grocery.py", "test_grocery.py"):
        shutil.copy(os.path.join(SRC, "review", "base", name), work)
    git(work, "add", "--", "grocery.py", "test_grocery.py")
    git(work, "commit", "-q", "-m", "base")
    git(work, "checkout", "-q", "-b", "change")
    patch = os.path.join(SRC, "review", "change.patch")
    if subprocess.run(["git", "-C", work, "apply", patch], capture_output=True).returncode:
        die("could not apply review/change.patch")
    for args in (("add", "--", "cost.py", "grocery.py", "test_grocery.py"), ("commit", "-q", "-m", "change")):
        git(work, *args)

    head = git(work, "rev-parse", "HEAD")
    diff = git(work, "diff", "main...HEAD")
    status_before = git(work, "status", "--porcelain", "--untracked-files=all")
    rc, secs, timed_out, answer = run_slot(work, base, "review", REVIEW_PROMPT.format(head=head, diff=diff), slot)
    unchanged = head == git(work, "rev-parse", "HEAD") and status_before == git(
        work, "status", "--porcelain", "--untracked-files=all")

    raw = [line.rstrip("\r") for line in answer.splitlines()]
    last = next((line.strip() for line in reversed(raw) if line.strip()), "")
    verdict = last.split()[-1] if last in ("VERDICT: PASS", "VERDICT: FIX") else "NONE"

    print("REVIEW %s secs=%d exit=%d tree_unchanged=%s verdict=%s" % (label, secs, rc, "yes" if unchanged else "no", verdict))
    for line in [line for line in raw if line.startswith(("P1:", "P2:"))][:12]:
        print(line[:240])
    reject(rc, timed_out, "" if unchanged else "the tree changed",
           "" if verdict != "NONE" else "no valid VERDICT line")
def main(argv):
    if len(argv) < 3 or argv[1] not in ("worker", "review") or not argv[2]:
        print("usage: %s worker|review '<slot command>' [label]" % os.path.basename(argv[0]), file=sys.stderr)
        return 2
    base = tempfile.mkdtemp(prefix="belt-trial.")
    try:
        (worker if argv[1] == "worker" else review)(base, argv[2], argv[3] if len(argv) > 3 else argv[1])
    finally:
        shutil.rmtree(base, ignore_errors=True)
if __name__ == "__main__": sys.exit(main(sys.argv))
