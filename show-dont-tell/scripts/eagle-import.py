#!/usr/bin/env python3
"""Import one original output into an explicitly named, currently open Eagle library.

--library current   use whichever library is open (its name is printed in the result).
--folder A/B/C      a nested path; with --create-folder, every missing level is created under its parent.
--metadata          optional: without it, the newest line for this file in the image-log.jsonl next to it
                    (prompt, model, settings, refs, size) becomes the annotation.
"""
import argparse
import hashlib
import json
import time
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

BASE = "http://localhost:41595/api/"


def api(route, payload=None):
    data = None if payload is None else json.dumps(payload, ensure_ascii=False).encode()
    req = Request(BASE + route, data=data, headers={"Content-Type": "application/json"})
    with urlopen(req, timeout=30) as response:
        result = json.load(response)
    if result.get("status") != "success":
        raise RuntimeError(f"Eagle {route}: {result.get('status', 'unknown error')}")
    return result.get("data")


def assert_library(expected):
    lib = api("library/info")["library"]
    if expected != "current" and expected not in (lib.get("name"), lib.get("path")):
        raise RuntimeError(f"Wrong open library: {lib.get('name')!r}; expected {expected!r}")
    return lib


def flatten(folders, parent=""):
    for folder in folders:
        path = f"{parent}/{folder['name']}" if parent else folder["name"]
        yield path, folder
        yield from flatten(folder.get("children", []), path)


def find_folder(folders, target):
    matches = [f for path, f in flatten(folders) if target in (path, f["id"])]
    if len(matches) > 1:
        raise RuntimeError("Ambiguous folder; supply the unique full path or ID")
    return matches[0] if matches else None


def matching_items(folder_id, marker):
    offset = 0
    while True:
        batch = api("item/list?" + urlencode({"folders": folder_id, "limit": 200, "offset": offset}))
        for item in batch:
            if not item.get("isDeleted") and marker in item.get("annotation", ""):
                yield item
        if len(batch) < 200:
            break
        offset += len(batch)


def from_log(image):
    """The newest image-log.jsonl line (next to the image) whose output is this file."""
    log = image.parent / "image-log.jsonl"
    hit = None
    if log.is_file():
        for line in log.read_text(encoding="utf-8").splitlines():
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if rec.get("out") and "stopped" not in rec and Path(rec["out"]).name == image.name:
                hit = rec
    if not hit:
        return {"note": "no image-log.jsonl line for this file"}
    keep = ("time", "model", "settings", "size_px", "refs", "prompt")
    return {k: hit[k] for k in keep if hit.get(k) not in (None, "", [])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for flag in ("file", "library", "folder", "name"):
        parser.add_argument("--" + flag, required=True)
    parser.add_argument("--metadata", help="JSON file; default: this file's line in image-log.jsonl")
    parser.add_argument("--create-folder", action="store_true")
    args = parser.parse_args()
    image = Path(args.file).expanduser().resolve(strict=True)
    if not image.is_file() or image.stat().st_size == 0:
        raise RuntimeError("Output must be an existing nonempty file")
    metadata = json.loads(Path(args.metadata).read_text()) if args.metadata else from_log(image)
    if not isinstance(metadata, dict):
        raise RuntimeError("Metadata must be a JSON object")
    tags = metadata.get("tags", [])
    if not isinstance(tags, list) or not all(isinstance(t, str) for t in tags):
        raise RuntimeError("tags must be an array of strings")
    marker = "source_sha256=" + hashlib.sha256(image.read_bytes()).hexdigest()
    annotation = marker + "\n" + json.dumps(metadata, ensure_ascii=False, indent=2)
    lib = assert_library(args.library)
    folder = find_folder(api("folder/list"), args.folder)
    if folder is None:
        if not args.create_folder:
            raise RuntimeError("Folder not found; creation requires --create-folder")
        parent, path = None, ""
        for part in args.folder.split("/"):      # create each missing level under its parent
            path = f"{path}/{part}" if path else part
            found = find_folder(api("folder/list"), path)
            if found is None:
                assert_library(args.library)
                found = api("folder/create", {"folderName": part, **({"parent": parent} if parent else {})})
            parent = found["id"]
        folder = found
    folder_id = folder["id"]
    existing = list(matching_items(folder_id, marker))
    if len(existing) > 1:
        raise RuntimeError("Multiple existing copies found; inspect Eagle before importing")
    if not existing:
        assert_library(args.library)
        api("item/addFromPath", {"path": str(image), "name": args.name,
                               "website": metadata.get("source_url", ""), "tags": tags,
                               "annotation": annotation, "folderId": folder_id})
        # Eagle acknowledges the import before its list index is necessarily updated.
        # Poll reads only; never repeat the add while its outcome is ambiguous.
        for attempt in range(10):
            assert_library(args.library)
            existing = list(matching_items(folder_id, marker))
            if existing:
                break
            time.sleep(0.5)
    assert_library(args.library)
    if len(existing) != 1 or folder_id not in existing[0].get("folders", []):
        raise RuntimeError("Import not verified; inspect Eagle before retrying")
    item = existing[0]
    print(json.dumps({"status": "verified", "library": lib["name"], "folder": folder["name"],
                      "folder_id": folder_id, "item_id": item["id"], "name": item["name"],
                      "width": item.get("width"), "height": item.get("height")}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as e:
        hint = " Ask the user to open that library in Eagle, then rerun." if "Wrong open library" in str(e) else ""
        raise SystemExit(f"REFUSED: {e}. Nothing was imported.{hint}")
    except OSError as e:   # Eagle closed, or its API not reachable (URLError is an OSError)
        raise SystemExit(f"REFUSED: Eagle is not reachable at {BASE} ({e}). Nothing was imported. Ask the user to start Eagle, then rerun.")
