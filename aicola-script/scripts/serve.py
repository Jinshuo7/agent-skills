#!/usr/bin/env python3
"""Local review page for an aicola pack: read, edit, check, then fill aicola.

  serve.py <pack dir> [--port 8765]     then open http://127.0.0.1:8765

Save writes the fields back to the pack's files and reruns check.py.
"Fill aicola" runs fill.py in the background; its log streams into the page.
Listens on 127.0.0.1 only.
"""
import argparse, json, subprocess, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from fields import FIELDS, field_path, read_field, load_settings  # noqa: E402

PACK: Path = None
FILL = {"proc": None, "log": ""}


def pack_json():
    def j(name, default):
        p = PACK / name
        return json.loads(p.read_text(encoding="utf-8")) if p.exists() else default
    return {
        "pack": str(PACK),
        "fields": [{"key": k, "file": f, "label": l, "limit": lim, "text": read_field(PACK, k)}
                   for k, f, l, lim in FIELDS],
        "settings": load_settings(PACK),
        "check": j("check.json", []),
        "todo": (PACK / "todo.md").read_text(encoding="utf-8") if (PACK / "todo.md").exists() else "",
        "project": j("fill-state.json", {}).get("project", ""),
        "filling": FILL["proc"] is not None and FILL["proc"].poll() is None,
    }


def run_check():
    subprocess.run([sys.executable, str(HERE / "check.py"), str(PACK)], capture_output=True)


def start_fill(project, dry):
    cmd = [sys.executable, "-u", str(HERE / "fill.py"), str(PACK), "--project", project]
    if dry:
        cmd.append("--dry-run")
    FILL["log"] = "$ " + " ".join(cmd[2:]) + "\n"
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    FILL["proc"] = p

    def pump():
        for line in p.stdout:
            FILL["log"] += line
        p.wait()
        FILL["log"] += f"\n[exit {p.returncode}]\n"
    threading.Thread(target=pump, daemon=True).start()


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body, ctype="application/json"):
        b = body if isinstance(body, bytes) else body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path == "/":
            return self.send(200, (HERE / "review.html").read_bytes(), "text/html")
        if self.path == "/api/pack":
            return self.send(200, json.dumps(pack_json(), ensure_ascii=False))
        if self.path == "/api/fill-log":
            running = FILL["proc"] is not None and FILL["proc"].poll() is None
            return self.send(200, json.dumps({"log": FILL["log"], "running": running}, ensure_ascii=False))
        self.send(404, "{}")

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        data = json.loads(self.rfile.read(n) or b"{}")
        if self.path == "/api/save":
            for k, text in data.get("fields", {}).items():
                field_path(PACK, k).write_text(text, encoding="utf-8")
            if "settings" in data:
                (PACK / "settings.json").write_text(
                    json.dumps(data["settings"], ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            run_check()
            return self.send(200, json.dumps(pack_json(), ensure_ascii=False))
        if self.path == "/api/fill":
            if FILL["proc"] is not None and FILL["proc"].poll() is None:
                return self.send(409, json.dumps({"error": "a fill is already running"}))
            project = (data.get("project") or "").strip()
            if not project:
                return self.send(400, json.dumps({"error": "project name needed"}))
            start_fill(project, bool(data.get("dry")))
            return self.send(200, "{}")
        self.send(404, "{}")


def main():
    global PACK
    ap = argparse.ArgumentParser()
    ap.add_argument("pack")
    ap.add_argument("--port", type=int, default=8765)
    a = ap.parse_args()
    PACK = Path(a.pack).resolve()
    run_check()
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), H)
    print(f"review page: http://127.0.0.1:{a.port}  (pack {PACK})", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
