---
name: bambu-print-handoff
description: Hand a 3D print job to BambuStudio on this Mac — unpack the archive, open the parts, flag plate-fit and orientation problems, then stop at the slicer. Use when a print folder or zip arrives (STL/STEP/3MF), or the user says "print these", "send it to my Bambu / the A1", "slice these parts", or asks whether a model fits the bed or needs flipping.
---

# Bambu print hand-off

Everything up to the slicer is yours. Slicing and the Print button belong to the human, who knows the material, the plate and the deadline. You deliver a loaded app plus an honest pre-flight; they decide what runs.

Target: Bambu Lab A1, 0.4 mm nozzle, 256 × 256 × 256 mm bed.

## 1. Unpack

CAD exports routinely carry UTF-8 filenames without the UTF-8 flag, so both `unzip` and Python decode them as CP437 and hand back mojibake. Repair the name, never the bytes:

```python
name = entry.filename.encode("cp437").decode("utf-8")
```

Extract into a new folder named after the archive; refuse to clobber one that exists. Done when every entry is on disk under its real name and no filename renders as `?` or mojibake.

## 2. Sort the parts

Open the **STL** files; STEP is the same geometry in CAD form and the slicer has no use for it. Read the filenames for multiplicity: `_x3` and similar usually mean *print three copies*, while the file itself holds a single body — confirm by triangle count rather than assuming either way.

Done when each printable part is named with its size and its copy count.

## 3. Pre-flight the geometry

Both checks are read-only. Run `parts.py` beside this file, or reproduce it:

```bash
python3 parts.py <folder>/*.stl
```

It reports, per part: bounding box, min z, and the largest downward-facing flat area with its height.

**Plate fit.** Sum footprints against 65,536 mm² (the 256² bed) and check no part exceeds 256 mm on any axis. A set over that does not shrink to fit — it needs a split, so name the plates and the parts on each.

**Orientation.** CAD parts sit in assembly position, so the lowest face is often not the bed:

- min z ≈ 0 with the dominant down-face there → prints as modelled.
- min z > 0 → it floats; its largest down-face is usually a roof interior, so the part wants flipping onto that face.
- min z < 0 → a feature hangs below the plate; 180° about X typically lands the flat face on the bed.

Report the verdict per part. The human performs the flips.

## 4. Open it in the app

```bash
open -a /Applications/BambuStudio.app <part1.stl> <part2.stl> ...
```

BambuStudio takes a while on a cold start: wait ~25 s, then take a screenshot and read it before saying anything landed.

Two things routinely show up and both are worth reporting verbatim:

- **A grouped import.** Several files opened together can arrive as *one* object — the toast names the first file but reports a bounding box and triangle count matching the whole set. The human needs right-click → **Split → To objects** before arranging, or they will move every part at once.
- **A boundary error.** Expected whenever the set exceeds one plate. It is information, not a bug to fix.

Done when the screenshot shows the parts loaded and you can quote what the app is complaining about.

## 5. Report, then stop

One short table: part, size, verdict (as-modelled / flip / copies needed). Then the plate split and the app's own warnings.

Done when the human can act without opening the files themselves. At that point they slice and print; you are finished.

## Reference

`printer-api.md` — what this A1's local ports actually allow. Read it before answering "can't you just send the job?", so the answer comes from measurement instead of a fresh investigation.
