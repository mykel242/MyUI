#!/usr/bin/env python3
"""diff_shots.py -- one job: compare a run's frame boxes against the approved ones.

Only the rectangles the harness recorded are compared. The world behind the
HUD is ignored, so a shot taken in a different spot still diffs cleanly as long
as nothing MyUI draws has changed.

For every frame in every shot:
  geometry  the recorded rect against the approved rect, in pixels
  pixels    the crop against the approved crop: share of pixels whose largest
            channel difference exceeds --threshold

Writes shots/results/<shape>/<run-id>/ with one diff image per frame
(approved | this run | changes in red) plus report.md and report.json, and
points shots/results/LATEST.md at it.

    tools/diff_shots.py                      the newest filed run of each shape
    tools/diff_shots.py shots/runs/<shape>/<run-id>
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import shotlib  # noqa: E402

shotlib.need_pillow()
from PIL import Image, ImageChops, ImageOps  # noqa: E402

MIN_ALPHA = 0.01


def latest_runs() -> list[Path]:
    out = []
    for shape in sorted(p for p in shotlib.RUNS.glob("*") if p.is_dir()):
        runs = sorted(p for p in shape.glob("*") if (p / "manifest.json").exists())
        if runs:
            out.append(runs[-1])
    return out


def drawn(frame: dict) -> bool:
    if not frame.get("visible") or frame.get("w") is None:
        return False
    a = frame.get("alpha")
    return a is None or a > MIN_ALPHA     # unreadable (secret) alpha: compare anyway


def changed_mask(a: Image.Image, b: Image.Image, threshold: int) -> tuple[Image.Image, float]:
    diff = ImageChops.difference(a.convert("RGB"), b.convert("RGB"))
    r, g, bl = diff.split()
    biggest = ImageChops.lighter(ImageChops.lighter(r, g), bl)
    mask = biggest.point(lambda v: 255 if v > threshold else 0)
    hist = mask.histogram()
    total = a.width * a.height
    return mask, (hist[255] / total if total else 0.0)


def diff_image(approved: Image.Image | None, current: Image.Image, mask: Image.Image | None) -> Image.Image:
    """approved | current | changes, scaled up so thin HUD elements are visible."""
    panels = []
    if approved is not None:
        panels.append(approved.convert("RGB"))
    panels.append(current.convert("RGB"))
    if mask is not None:
        base = ImageOps.grayscale(current).convert("RGB").point(lambda v: v // 3)
        red = Image.new("RGB", current.size, (255, 40, 40))
        panels.append(Image.composite(red, base, mask))
    h = max(p.height for p in panels)
    scale = max(1, min(8, 80 // max(1, h)))
    panels = [p.resize((p.width * scale, p.height * scale), Image.NEAREST) for p in panels]
    gap = 6
    w = sum(p.width for p in panels) + gap * (len(panels) - 1)
    out = Image.new("RGB", (w, max(p.height for p in panels)), (40, 40, 48))
    x = 0
    for p in panels:
        out.paste(p, (x, 0))
        x += p.width + gap
    return out


def geometry_delta(a: dict, b: dict, size: tuple[int, int]) -> float:
    W, H = size
    return max(abs(a[k] - b[k]) * (W if k in ("x", "w") else H) for k in ("x", "y", "w", "h"))


def diff_run(run_dir: Path, threshold: int, tolerance: float, geometry_px: float) -> dict:
    run = shotlib.load_manifest(run_dir)
    shape = run.get("shape") or shotlib.shape_of(run)
    out_dir = shotlib.RESULTS / shape / run["id"]
    out_dir.mkdir(parents=True, exist_ok=True)

    report = {"run": run["id"], "shape": shape, "build": run.get("build"),
              "myui": run.get("myui"), "screen": run.get("screen"),
              "frames": [], "checks": run.get("checks") or [],
              "skipped": run.get("skipped") or [], "errors": run.get("errors") or []}

    for shot in run.get("shots") or []:
        key = shotlib.test_key(shot)
        img_path = run_dir / (shot.get("file") or shotlib.shot_filename(shot))
        if not img_path.exists():
            report["frames"].append({"test": key, "frame": "-", "status": "missing-shot"})
            continue
        img = Image.open(img_path)
        for frame in shot.get("frames") or []:
            row = {"test": key, "frame": frame["name"], "what": shot.get("what")}
            if not drawn(frame):
                row["status"] = "not-drawn"
                report["frames"].append(row)
                continue
            box = shotlib.crop_box(frame, img.size)
            if box is None:
                row["status"] = "off-screen"
                report["frames"].append(row)
                continue
            crop = img.crop(box)
            appr_png = shotlib.APPROVED / shape / key / f"{shotlib.safe_name(frame['name'])}.png"
            appr_json = appr_png.with_suffix(".json")
            dest = out_dir / key / f"{shotlib.safe_name(frame['name'])}.png"
            dest.parent.mkdir(parents=True, exist_ok=True)

            if not appr_png.exists():
                row["status"] = "new"
                diff_image(None, crop, None).save(dest)
            else:
                approved = Image.open(appr_png)
                problems = []
                if appr_json.exists():
                    rect = json.loads(appr_json.read_text())
                    moved = geometry_delta(rect, frame, img.size)
                    row["moved_px"] = round(moved, 2)
                    if moved > geometry_px:
                        problems.append(f"moved {moved:.1f}px")
                # Rounding a normalised rect can land a pixel either way; a
                # one- or two-pixel size wobble compares on the common area.
                dw, dh = abs(approved.width - crop.width), abs(approved.height - crop.height)
                if (dw or dh) and dw <= 2 and dh <= 2:
                    w, h = min(approved.width, crop.width), min(approved.height, crop.height)
                    approved, crop = approved.crop((0, 0, w, h)), crop.crop((0, 0, w, h))
                if shot.get("world"):
                    # Shot over the world on purpose: the pixels are scenery.
                    row["changed"] = None
                    row["review"] = True
                    diff_image(approved, crop, None).save(dest)
                elif approved.size != crop.size:
                    problems.append(f"size {approved.size} -> {crop.size}")
                    row["changed"] = None
                    diff_image(approved, crop, None).save(dest)
                else:
                    mask, share = changed_mask(approved, crop, threshold)
                    row["changed"] = round(share, 5)
                    if share > tolerance:
                        problems.append(f"{share:.2%} of pixels changed")
                    diff_image(approved, crop, mask).save(dest)
                row["status"] = "fail" if problems else "pass"
                if problems:
                    row["why"] = "; ".join(problems)
            row["diff"] = str(dest.relative_to(shotlib.REPO))
            report["frames"].append(row)

    (out_dir / "report.json").write_text(json.dumps(report, indent=2))
    md = render(report)
    (out_dir / "report.md").write_text(md)
    latest = shotlib.RESULTS / "LATEST.md"
    latest.write_text(f"Latest: [{shape}/{run['id']}]({shape}/{run['id']}/report.md)\n\n" + md)
    return report


def render(r: dict) -> str:
    counts: dict[str, int] = {}
    for f in r["frames"]:
        counts[f["status"]] = counts.get(f["status"], 0) + 1
    failed_checks = [c for c in r["checks"] if not c.get("ok")]
    lines = [f"# Run {r['run']} — {r['shape']}", "",
             f"MyUI {r.get('myui')} · build {r.get('build')}", "",
             "**Frames:** " + ", ".join(f"{v} {k}" for k, v in sorted(counts.items())),
             f"**Checks:** {len(r['checks']) - len(failed_checks)} passed, {len(failed_checks)} failed", ""]
    if r["errors"]:
        lines += ["## Harness errors", ""] + [f"- {e}" for e in r["errors"]] + [""]
    if r["skipped"]:
        lines += ["## Skipped suites", ""] + [f"- {s.get('suite')}: {s.get('why')}" for s in r["skipped"]] + [""]
    if failed_checks:
        lines += ["## Failed checks", ""] + [f"- {c['suite']}/{c['test']}: {c.get('detail')}" for c in failed_checks] + [""]
    lines += ["## Frames", "", "| test | frame | status | detail |", "|---|---|---|---|"]
    for f in r["frames"]:
        detail = f.get("why") or ""
        if f.get("changed") is not None and not detail:
            detail = f"{f['changed']:.3%} changed"
        if f.get("review") and not detail:
            detail = "over the world: geometry only, look at it"
        if f.get("diff"):
            detail = f"{detail} [diff]({Path(f['diff']).relative_to(Path('shots/results') / r['shape'] / r['run'])})".strip()
        lines.append(f"| {f['test']} | {f['frame']} | {f['status']} | {detail} |")
    lines += ["", "## Checks", ""]
    for c in r["checks"]:
        lines.append(f"- {'pass' if c.get('ok') else '**FAIL**'} {c['suite']}/{c['test']}: {c.get('detail') or ''}")
    return "\n".join(lines) + "\n"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("runs", nargs="*", type=Path)
    ap.add_argument("--threshold", type=int, default=32, help="per-pixel channel difference that counts")
    ap.add_argument("--tolerance", type=float, default=0.01, help="share of changed pixels that fails")
    ap.add_argument("--geometry-px", type=float, default=1.0, help="rect movement that fails")
    args = ap.parse_args(argv)

    runs = [p.resolve() for p in args.runs] or latest_runs()
    if not runs:
        print("no filed runs -- tools/watch_shots.py files them")
        return 1
    worst = 0
    for run_dir in runs:
        r = diff_run(run_dir, args.threshold, args.tolerance, args.geometry_px)
        statuses = [f["status"] for f in r["frames"]]
        bad = statuses.count("fail") + statuses.count("missing-shot") + sum(1 for c in r["checks"] if not c.get("ok"))
        print(f"{r['shape']}/{r['run']}: " + ", ".join(f"{statuses.count(s)} {s}" for s in sorted(set(statuses)))
              + f"; checks {sum(1 for c in r['checks'] if c.get('ok'))}/{len(r['checks'])}")
        print(f"  report: {(shotlib.RESULTS / r['shape'] / r['run'] / 'report.md').relative_to(shotlib.REPO)}")
        worst = max(worst, 1 if bad else 0)
    return worst


if __name__ == "__main__":
    sys.exit(main())
