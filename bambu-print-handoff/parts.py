#!/usr/bin/env python3
"""Per-part geometry report for a Bambu print pre-flight.

Usage:
    python3 parts.py file1.stl file2.stl ...
    python3 parts.py folder/*.stl

Reports bounding box, min z, the largest downward-facing flat area (the face
that wants to be on the bed), and a plate-fit total. Read-only.
"""
import math
import struct
import sys
from collections import defaultdict

BED = 256.0


def closest_flat_faces(path):
    """Return bbox + the down-facing flat-area histogram for one binary STL."""
    with open(path, "rb") as fh:
        head = fh.read(84)
    if len(head) < 84:
        raise ValueError(f"{path}: not a binary STL")
    count = struct.unpack("<I", head[80:84])[0]
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    down = defaultdict(float)
    up = defaultdict(float)
    with open(path, "rb") as fh:
        fh.seek(84)
        for _ in range(count):
            rec = fh.read(50)
            if len(rec) < 50:
                break
            pts = [struct.unpack("<3f", rec[12 + i * 12: 24 + i * 12]) for i in range(3)]
            for px, py, pz in pts:
                lo = [min(lo[0], px), min(lo[1], py), min(lo[2], pz)]
                hi = [max(hi[0], px), max(hi[1], py), max(hi[2], pz)]
            a, b, c = pts
            ux, uy, uz = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
            vx, vy, vz = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
            nx, ny, nz = (uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
            norm = (nx * nx + ny * ny + nz * nz) ** 0.5
            if not norm:
                continue
            area = norm / 2.0
            zc = (a[2] + b[2] + c[2]) / 3.0
            if nz / norm < -0.85:
                down[round(zc, 1)] += area
            elif nz / norm > 0.85:
                up[round(zc, 1)] += area
    return lo, hi, down, up


def verdict(min_z, down, min_area):
    if min_z < -0.05:
        return "flip 180deg about X (feature hangs under the plate)"
    if min_z > 0.05:
        return f"flip onto its flat face (floats {min_z:.1f} mm above bed)"
    if min_area < 120:
        return "as modelled, but the bed contact is small -- eyeball for supports"
    return "as modelled"


def main(paths):
    if not paths:
        print(__doc__)
        return 1
    total_footprint = 0.0
    rows = []
    for path in paths:
        lo, hi, down, up = closest_flat_faces(path)
        size = [hi[i] - lo[i] for i in range(3)]
        min_z = lo[2]
        near_bed = sum(a for z, a in down.items() if z < min_z + 1.0)
        big = max(down.items(), key=lambda kv: kv[1]) if down else (0.0, 0.0)
        footprint = size[0] * size[1]
        total_footprint += footprint
        name = path.rsplit("/", 1)[-1]
        rows.append((name, size, min_z, big, near_bed, verdict(min_z, down, near_bed),
                     footprint, footprint > BED * BED * 0.98 or max(size[:2]) > BED))

    print(f"{'part':44s} {'W x D x H (mm)':>22s} {'min z':>7s}  verdict")
    for name, size, min_z, big, near_bed, verd, _fp, _over in rows:
        dims = f"{size[0]:.1f} x {size[1]:.1f} x {size[2]:.1f}"
        print(f"{name[:44]:44s} {dims:>22s} {min_z:7.2f}  {verd}")

    print()
    beds = total_footprint / (BED * BED)
    print(f"total footprint {total_footprint:,.0f} mm2 = {beds:.2f} x a {BED:.0f}x{BED:.0f} bed "
          f"-> at least {max(1, math.ceil(beds))} plate(s) by area")
    over = [r[0] for r in rows if r[7]]
    if over:
        print("parts that alone approach or exceed the bed: " + ", ".join(over))
    wide = [r for r in rows if r[1][0] + r[1][1] > 0]
    if len(wide) > 1:
        biggest = max(rows, key=lambda r: r[1][0] * r[1][1])
        print(f"largest part: {biggest[0]} at {biggest[1][0]:.1f} x {biggest[1][1]:.1f} mm "
              f"-- two like it cannot share a plate")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
