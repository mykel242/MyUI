#!/usr/bin/env python3
"""Offline tests for tools/: SavedVariables reading, filing, diffing, approving.

Run with Pillow available (smoke.sh uses tools/.venv/bin/python).
Builds a fake WoW folder and repo layout in a temp dir, so nothing real is
touched: a finished run in SavedVariables, matching screenshots on disk, then
file -> diff (new) -> approve -> diff (pass) -> change a frame -> diff (fail).
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent / "tools"
sys.path.insert(0, str(TOOLS))

import shotlib  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402


def lua(v, indent=0) -> str:
    """Emit a value the way the client writes SavedVariables."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if v is None:
        return "nil"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    pad = "\t" * (indent + 1)
    if isinstance(v, list):
        body = "".join(f"{pad}{lua(x, indent + 1)}, -- [{i}]\n" for i, x in enumerate(v, 1))
    else:
        body = "".join(f'{pad}["{k}"] = {lua(x, indent + 1)},\n' for k, x in v.items())
    return "{\n" + body + "\t" * indent + "}"


class Parser(unittest.TestCase):
    def test_wow_shapes(self):
        text = (
            'MyUITestDB = {\n["runs"] = {\n{\n["id"] = "20261114-120000",\n'
            '["finished"] = true,\n["n"] = -3,\n["f"] = 0.25,\n["e"] = 1e-05,\n'
            '["s"] = "a \\"quote\\"\\nline",\n["empty"] = {\n},\n'
            '["list"] = {\n"x", -- [1]\n"y", -- [2]\n},\n},\n},\n}\n'
            'Other = nil\n'
        )
        path = Path(tempfile.mkstemp(suffix=".lua")[1])
        path.write_text(text)
        sv = shotlib.read_saved_variables(path)
        run = sv["MyUITestDB"]["runs"][0]
        self.assertEqual(run["id"], "20261114-120000")
        self.assertIs(run["finished"], True)
        self.assertEqual(run["n"], -3)
        self.assertAlmostEqual(run["f"], 0.25)
        self.assertAlmostEqual(run["e"], 1e-05)
        self.assertEqual(run["s"], 'a "quote"\nline')
        self.assertEqual(run["empty"], [])
        self.assertEqual(run["list"], ["x", "y"])
        self.assertIsNone(sv["Other"])

    def test_round_trip_of_emitter(self):
        data = {"runs": [{"id": "r", "shots": [{"n": 1, "frames": [{"name": "A", "x": 0.5}]}]}]}
        path = Path(tempfile.mkstemp(suffix=".lua")[1])
        path.write_text("MyUITestDB = " + lua(data) + "\n")
        self.assertEqual(shotlib.read_saved_variables(path)["MyUITestDB"], data)


class Geometry(unittest.TestCase):
    def test_crop_box(self):
        f = {"x": 0.1, "y": 0.2, "w": 0.3, "h": 0.1}
        self.assertEqual(shotlib.crop_box(f, (1000, 500), pad=0), (100, 100, 400, 150))
        self.assertEqual(shotlib.crop_box(f, (1000, 500)), (98, 98, 402, 152))
        self.assertIsNone(shotlib.crop_box({"x": None}, (10, 10)))
        self.assertIsNone(shotlib.crop_box({"x": 2.0, "y": 0, "w": 0.1, "h": 0.1}, (100, 100)))

    def test_shapes(self):
        self.assertEqual(shotlib.shape_of({"screen": {"physical": {"w": 3456, "h": 2234}}}), "laptop-3456x2234")
        self.assertEqual(shotlib.shape_of({"screen": {"physical": {"w": 5120, "h": 1440}}}), "ultrawide-5120x1440")
        self.assertEqual(shotlib.shape_of({"screen": {"physical": {"w": 5120, "h": 2880}}}), "laptop-5120x2880")


SIZE = (400, 200)
FRAMES = [
    {"name": "SelfStack", "x": 0.40, "y": 0.70, "w": 0.20, "h": 0.10, "visible": True, "alpha": 0.35},
    {"name": "TargetStrip", "x": 0.40, "y": 0.10, "w": 0.20, "h": 0.05, "visible": True, "alpha": 0},
]


def screenshot(path: Path, colour=(200, 220, 255), offset=0):
    img = Image.new("RGB", SIZE, (30, 60, 30))            # "the world"
    d = ImageDraw.Draw(img)
    f = FRAMES[0]
    l, t = int(f["x"] * SIZE[0]) + offset, int(f["y"] * SIZE[1])
    d.rectangle([l + 4, t + 4, l + int(f["w"] * SIZE[0]) - 4, t + int(f["h"] * SIZE[1]) - 4], fill=colour)
    img.save(path)


class Pipeline(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.wow = self.tmp / "_retail_"
        (self.wow / "Screenshots").mkdir(parents=True)
        sv_dir = self.wow / "WTF" / "Account" / "ACCT" / "SavedVariables"
        sv_dir.mkdir(parents=True)
        self.sv = sv_dir / "MyUI_Test.lua"
        repo = self.tmp / "repo"
        shotlib.REPO = repo
        shotlib.SHOTS = repo / "shots"
        shotlib.RUNS = shotlib.SHOTS / "runs"
        shotlib.RESULTS = shotlib.SHOTS / "results"
        shotlib.APPROVED = shotlib.SHOTS / "approved"
        import importlib
        import watch_shots
        import diff_shots
        import approve_shots
        self.watch = importlib.reload(watch_shots)
        self.diff = importlib.reload(diff_shots)
        self.approve = importlib.reload(approve_shots)

    def write_run(self, run_id: str, t0: int, colour=(200, 220, 255), offset=0, frames=None):
        shots = []
        for n, test in enumerate(["rest", "show-on"], 1):
            t = t0 + 2 * n
            name = datetime.fromtimestamp(t).strftime("WoWScrnShot_%m%d%y_%H%M%S.png")
            screenshot(self.wow / "Screenshots" / name, colour, offset)
            shots.append({"n": n, "suite": "myui-p1", "test": test, "before": t, "after": t,
                          "result": "ok", "frames": frames or FRAMES, "what": test})
        run = {"id": run_id, "finished": True, "build": "12.1.5.70783", "myui": "test",
               "screen": {"physical": {"w": 3456, "h": 2234}}, "shots": shots,
               "checks": [{"suite": "myui-p1", "test": "rest", "ok": True, "detail": "fine"}],
               "skipped": [], "errors": []}
        existing = shotlib.harness_runs(self.sv) if self.sv.exists() else []
        self.sv.write_text("MyUITestDB = " + lua({"runs": [run] + existing}) + "\n")
        return run

    def args(self):
        class A:
            pass
        a = A()
        a.wow, a.then, a.dry_run = self.wow, None, False
        return a

    def test_file_diff_approve(self):
        t0 = int(datetime(2026, 11, 14, 12, 0, 0).timestamp())
        self.write_run("r1", t0)
        filed = self.watch.sweep(self.args())
        self.assertEqual(len(filed), 1)
        run_dir = filed[0]
        self.assertEqual(run_dir.parent.name, "laptop-3456x2234")
        self.assertTrue((run_dir / "01-myui-p1-rest.png").exists())
        self.assertTrue((run_dir / "02-myui-p1-show-on.png").exists())
        self.assertEqual(list((self.wow / "Screenshots").iterdir()), [], "screenshots were moved, not copied")
        self.assertEqual(self.watch.sweep(self.args()), [], "a filed run is not filed twice")

        r = self.diff.diff_run(run_dir, 32, 0.01, 1.0)
        statuses = {(f["test"], f["frame"]): f["status"] for f in r["frames"]}
        self.assertEqual(statuses[("myui-p1-rest", "SelfStack")], "new")
        self.assertEqual(statuses[("myui-p1-rest", "TargetStrip")], "not-drawn", "alpha 0 is not compared")
        self.assertTrue((shotlib.RESULTS / "LATEST.md").exists())

        self.assertEqual(self.approve.approve(run_dir, set()), 2)
        crop = shotlib.APPROVED / "laptop-3456x2234" / "myui-p1-rest" / "SelfStack.png"
        self.assertTrue(crop.exists())
        self.assertLess(Image.open(crop).width, SIZE[0], "approved shots are crops, not full screens")

        r = self.diff.diff_run(run_dir, 32, 0.01, 1.0)
        self.assertTrue(all(f["status"] in ("pass", "not-drawn") for f in r["frames"]), r["frames"])

        # Same layout, different colour inside the frame: a pixel failure.
        self.write_run("r2", t0 + 100, colour=(255, 80, 80))
        run2 = self.watch.sweep(self.args())[0]
        r = self.diff.diff_run(run2, 32, 0.01, 1.0)
        rest = next(f for f in r["frames"] if f["test"] == "myui-p1-rest" and f["frame"] == "SelfStack")
        self.assertEqual(rest["status"], "fail")
        self.assertIn("pixels changed", rest["why"])

        # The frame itself moved: a geometry failure, whatever the pixels say.
        moved = [dict(FRAMES[0], x=0.45), FRAMES[1]]
        self.write_run("r3", t0 + 200, frames=moved)
        run3 = self.watch.sweep(self.args())[0]
        r = self.diff.diff_run(run3, 32, 0.01, 1.0)
        rest = next(f for f in r["frames"] if f["test"] == "myui-p1-rest" and f["frame"] == "SelfStack")
        self.assertEqual(rest["status"], "fail")
        self.assertIn("moved", rest["why"])

    def test_missing_screenshot_waits(self):
        t0 = int(datetime(2026, 11, 14, 13, 0, 0).timestamp())
        self.write_run("r1", t0)
        for p in (self.wow / "Screenshots").iterdir():
            p.unlink()
            break
        self.assertEqual(self.watch.sweep(self.args()), [], "an incomplete run is not filed")


if __name__ == "__main__":
    unittest.main(verbosity=1)
