#!/usr/bin/env python3
"""approve_shots.py -- one job: promote a run's frame boxes to the approved baseline.

Crops each drawn frame out of the run's screenshots and writes it, with its
rect, to shots/approved/<shape>/<suite>-<test>/<frame>.png|.json. Only the
crops are kept -- never the full screen, which shows the world and can show
names. Approved crops are committed.

    tools/approve_shots.py shots/runs/<shape>/<run-id>               every test
    tools/approve_shots.py shots/runs/<shape>/<run-id> myui-p3-full  only these
    tools/approve_shots.py --latest myui-p1-rest
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import shotlib  # noqa: E402

shotlib.need_pillow()
from PIL import Image  # noqa: E402

MIN_ALPHA = 0.01


def drawn(frame: dict) -> bool:
    if not frame.get("visible") or frame.get("w") is None:
        return False
    a = frame.get("alpha")
    return a is None or a > MIN_ALPHA


def approve(run_dir: Path, only: set[str]) -> int:
    run = shotlib.load_manifest(run_dir)
    shape = run.get("shape") or shotlib.shape_of(run)
    count = 0
    for shot in run.get("shots") or []:
        key = shotlib.test_key(shot)
        if only and key not in only:
            continue
        img = Image.open(run_dir / (shot.get("file") or shotlib.shot_filename(shot)))
        dest = shotlib.APPROVED / shape / key
        for frame in shot.get("frames") or []:
            if not drawn(frame):
                continue
            box = shotlib.crop_box(frame, img.size)
            if box is None:
                continue
            dest.mkdir(parents=True, exist_ok=True)
            name = shotlib.safe_name(frame["name"])
            img.crop(box).save(dest / f"{name}.png")
            rect = {k: frame[k] for k in ("x", "y", "w", "h")}
            rect.update(run=run["id"], build=run.get("build"), myui=run.get("myui"),
                        screen=run.get("screen"))
            (dest / f"{name}.json").write_text(json.dumps(rect, indent=2, sort_keys=True))
            count += 1
        print(f"  approved {key}")
    return count


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("run", nargs="?", type=Path)
    ap.add_argument("tests", nargs="*", help="suite-test keys; default every test")
    ap.add_argument("--latest", action="store_true", help="use the newest filed run of each shape")
    args = ap.parse_args(argv)

    if args.latest:
        tests = ([str(args.run)] if args.run else []) + args.tests
        runs = []
        for shape in sorted(p for p in shotlib.RUNS.glob("*") if p.is_dir()):
            r = sorted(p for p in shape.glob("*") if (p / "manifest.json").exists())
            if r:
                runs.append(r[-1])
    elif args.run:
        tests, runs = args.tests, [args.run.resolve()]
    else:
        ap.error("name a run directory, or pass --latest")
    total = sum(approve(r, set(tests)) for r in runs)
    print(f"{total} frame box(es) approved")
    return 0 if total else 1


if __name__ == "__main__":
    sys.exit(main())
