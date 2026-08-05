#!/usr/bin/env python3
"""
Shrink the PUBLISHED figure copies for the web.

These plots are flat-colour dark-theme figures rendered at print resolution
(~2800x2600). Resizing barely helps (PNG already compresses them well, and
resampling adds antialiasing entropy) - but reducing the palette to 256 colours
roughly halves them with no visible change at screen size.

Only the *published copies* are touched:
    data/flux/fluxVSmortality/v10/...
    data/flux/ESA-FORTRACK/D2.2_datasets_and_tools/EFPs_mortality/...
The full-resolution originals in data/flux/plots/V10/ and every PDF are left
alone, so the manuscript figures are unaffected.

Idempotent: a file already in palette mode ("P") is skipped, so re-running after
a new sync only processes the newly copied figures.

    python3 scripts/optimize_published_pngs.py [--dry-run] [--jobs N] [target ...]
"""
import argparse, os, sys
from concurrent.futures import ProcessPoolExecutor, as_completed
from PIL import Image

ROOT = "/mnt/gsdata/projects/panops/panops-data-registry/data/flux"
DEFAULT_TARGETS = [
    f"{ROOT}/fluxVSmortality/v10",
    f"{ROOT}/ESA-FORTRACK/D2.2_datasets_and_tools/EFPs_mortality",
]
COLORS = 256


def process(path, dry_run=False):
    """Return (path, before, after) - after == before when skipped."""
    try:
        before = os.path.getsize(path)
        with Image.open(path) as im:
            if im.mode == "P":          # already quantised
                return (path, before, before)
            rgb = im.convert("RGB")
            q = rgb.quantize(colors=COLORS, method=Image.MEDIANCUT)
        if dry_run:
            import io
            buf = io.BytesIO()
            q.save(buf, "PNG", optimize=True)
            return (path, before, buf.tell())
        tmp = path + ".opt.tmp"
        q.save(tmp, "PNG", optimize=True)
        after = os.path.getsize(tmp)
        if after < before:
            os.replace(tmp, path)
        else:                            # never make a file bigger
            os.remove(tmp)
            after = before
        return (path, before, after)
    except Exception as e:               # noqa: BLE001 - report, don't abort the batch
        return (path, 0, 0, str(e))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("targets", nargs="*", default=None)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--jobs", type=int, default=16)
    a = ap.parse_args()

    targets = a.targets or DEFAULT_TARGETS
    files = []
    for t in targets:
        for dirpath, _, names in os.walk(t):
            files += [os.path.join(dirpath, n) for n in names if n.lower().endswith(".png")]
    if not files:
        print("no PNGs found under:", ", ".join(targets)); return

    print(f"{len(files)} PNGs under {len(targets)} target(s); "
          f"{'DRY RUN' if a.dry_run else f'quantising to {COLORS} colours'} with {a.jobs} workers")

    tot_b = tot_a = done = skipped = errors = 0
    with ProcessPoolExecutor(max_workers=a.jobs) as ex:
        futs = [ex.submit(process, f, a.dry_run) for f in files]
        for fut in as_completed(futs):
            r = fut.result()
            if len(r) == 4:
                errors += 1
                print(f"  ERROR {os.path.basename(r[0])}: {r[3]}", file=sys.stderr)
                continue
            _, b, af = r
            tot_b += b; tot_a += af
            if af == b: skipped += 1
            done += 1
            if done % 200 == 0:
                print(f"  {done}/{len(files)}  {tot_b/1e6:.0f} -> {tot_a/1e6:.0f} MB")

    print(f"\ndone: {done} files ({skipped} already optimised / unchanged, {errors} errors)")
    print(f"  before : {tot_b/1e6:8.1f} MB")
    print(f"  after  : {tot_a/1e6:8.1f} MB  ({100*tot_a/max(tot_b,1):.0f}% of original)")
    print(f"  saved  : {(tot_b-tot_a)/1e6:8.1f} MB")


if __name__ == "__main__":
    main()
