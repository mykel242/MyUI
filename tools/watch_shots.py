#!/usr/bin/env python3
"""watch_shots.py -- one job: move the harness's screenshots into the repo, named by test.

Waits for MyUI_Test's SavedVariables to show a finished run (the harness reloads
at the end of a run precisely so this file gets written), pairs each recorded
shot with the screenshot WoW wrote during it, and moves those files to

    shots/runs/<shape>/<run-id>/NN-<suite>-<test>.png   + manifest.json

Pairing is by time: the harness records the clock just before Screenshot() and
when the client confirms it, and WoW names files to the second. Shots are kept
more than a second apart, so each window holds exactly one file.

    tools/watch_shots.py                 keep watching (Ctrl-C to stop)
    tools/watch_shots.py --once          file anything unfiled, then exit
    tools/watch_shots.py --then tools/diff_shots.py
                                         after filing a run, run that command
                                         with the run directory appended

Diffing is a different tool's job; --then only hands over.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import shotlib  # noqa: E402

NAME = re.compile(r"^WoWScrnShot_(\d{6})_(\d{6})\.(png|jpg|jpeg|tga)$", re.I)


def screenshot_times(folder: Path) -> list[tuple[int, Path]]:
    out = []
    if not folder.is_dir():
        return out
    for p in folder.iterdir():
        m = NAME.match(p.name)
        if not m:
            continue
        stamp = datetime.strptime(m.group(1) + m.group(2), "%m%d%y%H%M%S")
        out.append((int(stamp.timestamp()), p))   # local time, as WoW writes it
    return sorted(out)


def filed_ids() -> set[str]:
    return {p.parent.name for p in shotlib.RUNS.glob("*/*/manifest.json")}


def pair(run: dict, shots_on_disk: list[tuple[int, Path]], slack: int = 1):
    """Map each recorded shot to one file. Returns (pairs, missing)."""
    used: set[Path] = set()
    pairs, missing = [], []
    for shot in run.get("shots") or []:
        lo = int(shot.get("before") or 0) - slack
        hi = int(shot.get("after") or shot.get("before") or 0) + slack
        hit = next((p for t, p in shots_on_disk if lo <= t <= hi and p not in used), None)
        if hit is None:
            missing.append(shot)
        else:
            used.add(hit)
            pairs.append((shot, hit))
    return pairs, missing


def file_run(run: dict, folder: Path, dry: bool = False) -> Path | None:
    pairs, missing = pair(run, screenshot_times(folder))
    if missing:
        names = ", ".join(shotlib.test_key(s) for s in missing[:5])
        print(f"  {run['id']}: {len(missing)} shot(s) not found yet ({names})")
        return None
    shape = shotlib.shape_of(run)
    dest = shotlib.RUNS / shape / run["id"]
    if dry:
        print(f"  would file {len(pairs)} shots to {dest}")
        return dest
    dest.mkdir(parents=True, exist_ok=True)
    for shot, src in pairs:
        target = dest / shotlib.shot_filename(shot)
        shutil.move(str(src), str(target))
        shot["file"] = target.name
        shot["source"] = src.name
    run["shape"] = shape
    (dest / "manifest.json").write_text(json.dumps(run, indent=2, sort_keys=True))
    print(f"  filed {run['id']}: {len(pairs)} shots -> {dest.relative_to(shotlib.REPO)}")
    for err in run.get("errors") or []:
        print(f"    harness error: {err}")
    return dest


def sweep(args) -> list[Path]:
    done = filed_ids()
    filed = []
    for sv in shotlib.saved_variables_files(args.wow):
        for run in shotlib.harness_runs(sv):
            if not isinstance(run, dict) or not run.get("finished"):
                continue
            if run.get("id") in done:
                continue
            dest = file_run(run, args.wow / "Screenshots", args.dry_run)
            if dest is not None:
                filed.append(dest)
                done.add(run["id"])
                if args.then and not args.dry_run:
                    subprocess.run([*args.then.split(), str(dest)], check=False)
    return filed


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--once", action="store_true", help="file anything unfiled and exit")
    ap.add_argument("--then", help="command to run on each filed run directory")
    ap.add_argument("--wow", type=Path, default=shotlib.WOW, help="the _retail_ folder")
    ap.add_argument("--interval", type=float, default=2.0)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)

    if args.once:
        filed = sweep(args)
        if not filed:
            print("nothing new to file")
        return 0

    print(f"watching {shotlib.compact(args.wow)} for finished runs (Ctrl-C to stop)")
    seen: dict[Path, float] = {}
    sweep(args)
    try:
        while True:
            time.sleep(args.interval)
            changed = False
            for sv in shotlib.saved_variables_files(args.wow):
                m = sv.stat().st_mtime
                if seen.get(sv) != m:
                    seen[sv] = m
                    changed = True
            if changed:
                # The client writes the file in one go on reload, but give it
                # a moment before reading a file that may still be open.
                time.sleep(0.5)
                sweep(args)
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
