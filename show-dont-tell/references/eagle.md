# Eagle import

In this skill, Eagle import runs after every round when the user config's `eagle.import` is true (SKILL.md step 6). The local API operates on whichever library is open at mutation time.

Additions to `eagle-import.py` in this skill (2026-11-22): `--library current` accepts the open library; `--folder A/B` with `--create-folder` creates each missing level under its parent; `--metadata` is optional, and without it the file's line in the `image-log.jsonl` next to it (if present) becomes the annotation.

## Procedure

1. Read `GET http://localhost:41595/api/library/info` and `/api/folder/list`. Verify the returned library name/path matches the user’s target. If the API is unavailable, check that Eagle is running; use its UI or report the blocked import. Do not edit `.library` internals.
2. Resolve a unique folder by its full hierarchy or ID. If absent, create it only when the requested destination permits creation, as in “put it in a folder such as X.” Duplicate names require a path/ID, not guessing. `POST /api/folder/create` accepts `folderName` and optional `parent`.
3. Save and inspect the original output locally. Use `scripts/eagle-import.py` with the exact expected library, folder and a metadata JSON file. `--create-folder` permits creating a missing root folder. The helper supports one file at a time and does not switch libraries.
4. The metadata JSON should record prompt, actual model/variant, size/ratio/quality/thinking/count, reference paths (only those actually used), source conversation URL, date and whether this is a concept or a real referenced SKU. Record observed costs separately from estimates. Optional `tags` must be an array of strings.
5. The helper adds the source-file SHA-256 to the annotation, checks for an already imported matching item, imports with `folderId`, then polls that folder briefly to verify membership. Eagle can acknowledge an import before the list index updates. A timed-out mutation is ambiguous: inspect Eagle before retrying. Never blindly repeat an add or folder-create request.

Example (all paths absolute):

```sh
python3 <skill>/scripts/eagle-import.py \
  --file /absolute/path/result.png \
  --library 'Exact current library name' \
  --folder '望远镜第一轮' --create-folder \
  --name '望远镜概念图 — GPT Image 2.6' \
  --metadata /absolute/path/generation.json
```

Eagle folders are catalog entries, not ordinary filesystem folders. Keep the downloaded output as a user-facing deliverable; importing a file does not require moving or deleting its original. Library names, folder IDs and project-specific preferences are runtime inputs, not global defaults for future tasks.

## API references

Verified against Eagle 4.0.0 legacy API on 2026-11-15. Newer versions also have a V2 API; do not mix their schemas.

- [Current library](https://api.eagle.cool/library/info)
- [Folder list](https://api.eagle.cool/folder/list)
- [Create folder](https://api.eagle.cool/folder/create)
- [Import local file](https://api.eagle.cool/item/add-from-path)
- [List and verify items](https://api.eagle.cool/item/list)

Avoid printing `/api/application/info` wholesale: its preferences may contain API tokens or other private configuration. These endpoints suffice without collecting that data.
