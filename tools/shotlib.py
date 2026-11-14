"""Shared plumbing for the screenshot tools. Not a tool itself.

Paths, the SavedVariables reader, and the on-disk layout under shots/:

    shots/runs/<shape>/<run-id>/            filed by watch_shots.py   (gitignored)
        NN-<suite>-<test>.png               full screenshots
        manifest.json                       the run, as the harness recorded it
    shots/results/<shape>/<run-id>/         written by diff_shots.py  (gitignored)
        <suite>-<test>/<frame>.png          diff image: approved | this run | changes
        report.json, report.md              what passed, failed, or is new
    shots/approved/<shape>/<suite>-<test>/  promoted by approve_shots.py (committed)
        <frame>.png                         cropped frame box, not the full screen
        <frame>.json                        its rect, for geometry comparison

Full screenshots are never committed: they show the world, and the world can
show names. Only cropped frame boxes are.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SHOTS = REPO / "shots"
RUNS = SHOTS / "runs"
RESULTS = SHOTS / "results"
APPROVED = SHOTS / "approved"

WOW = Path(os.environ.get("WOW_RETAIL", "/Applications/World of Warcraft/_retail_"))
SCREENSHOTS = WOW / "Screenshots"
SV_NAME = "MyUI_Test.lua"


def saved_variables_files(wow: Path = WOW) -> list[Path]:
    """Every account's copy of the harness's SavedVariables file."""
    return sorted((wow / "WTF" / "Account").glob(f"*/SavedVariables/{SV_NAME}"))


# ---------------------------------------------------------------------------
# SavedVariables reader
# ---------------------------------------------------------------------------
# WoW writes a restricted Lua subset: NAME = <value>, where a value is a
# string, number, boolean, nil or a table of ["key"] = value / [n] = value /
# bare positional values. That is all this parses.

class _Parser:
    _token = re.compile(r"""
        \s*(?:
          (?P<comment>--[^\n]*)
        | (?P<str>"(?:\\.|[^"\\])*")
        | (?P<num>-?(?:0x[0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?))
        | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
        | (?P<sym>[{}\[\]=,;])
        )""", re.X)

    def __init__(self, text: str):
        self.toks = []
        pos = 0
        while pos < len(text):
            m = self._token.match(text, pos)
            if not m or m.end() == pos:
                if text[pos:].strip() == "":
                    break
                raise ValueError(f"cannot parse SavedVariables near {text[pos:pos+40]!r}")
            pos = m.end()
            kind = m.lastgroup
            if kind == "comment" or kind is None:
                continue
            self.toks.append((kind, m.group(kind)))
        self.i = 0

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else (None, None)

    def take(self, sym=None):
        tok = self.peek()
        if sym is not None and tok[1] != sym:
            raise ValueError(f"expected {sym!r}, got {tok[1]!r}")
        self.i += 1
        return tok

    def value(self):
        kind, text = self.take()
        if kind == "str":
            return _unescape(text[1:-1])
        if kind == "num":
            v = float(int(text, 16)) if text.lower().startswith(("0x", "-0x")) else float(text)
            return int(v) if v.is_integer() and "." not in text and "e" not in text.lower() else v
        if kind == "name":
            return {"true": True, "false": False, "nil": None}.get(text, text)
        if text == "{":
            return self.table()
        raise ValueError(f"unexpected {text!r}")

    def table(self):
        out: dict = {}
        n = 1
        while self.peek()[1] != "}":
            if self.peek()[1] == "[":
                self.take("[")
                key = self.value()
                self.take("]")
                self.take("=")
                out[key] = self.value()
            elif self.peek()[0] == "name" and self.toks[self.i + 1][1] == "=":
                key = self.take()[1]
                self.take("=")
                out[key] = self.value()
            else:
                out[n] = self.value()
                n += 1
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        return _listify(out)

    def assignments(self):
        out = {}
        while self.peek()[0] is not None:
            _, name = self.take()
            self.take("=")
            out[name] = self.value()
        return out


def _unescape(s: str) -> str:
    return re.sub(r"\\(n|t|r|\\|\"|'|\d{1,3})",
                  lambda m: {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'"}
                  .get(m.group(1)) or chr(int(m.group(1))), s)


def _listify(d: dict):
    """A table whose keys are exactly 1..n becomes a list."""
    if d and all(isinstance(k, int) for k in d) and sorted(d) == list(range(1, len(d) + 1)):
        return [d[k] for k in range(1, len(d) + 1)]
    if not d:
        return []
    return d


def read_saved_variables(path: Path) -> dict:
    return _Parser(path.read_text(encoding="utf-8", errors="replace")).assignments()


def harness_runs(path: Path) -> list[dict]:
    db = read_saved_variables(path).get("MyUITestDB") or {}
    runs = db.get("runs") if isinstance(db, dict) else None
    return runs if isinstance(runs, list) else []


# ---------------------------------------------------------------------------
# Screen shapes
# ---------------------------------------------------------------------------

def shape_of(run: dict) -> str:
    """laptop-3456x2234 / ultrawide-5120x1440: approved shots are per shape."""
    phys = (run.get("screen") or {}).get("physical") or {}
    w, h = int(phys.get("w") or 0), int(phys.get("h") or 0)
    label = "ultrawide" if h and w / h > 2.0 else "wide" if h and w / h > 1.8 else "laptop"
    return f"{label}-{w}x{h}"


def shot_filename(shot: dict) -> str:
    return f"{int(shot['n']):02d}-{shot['suite']}-{shot['test']}.png"


def test_key(shot: dict) -> str:
    return f"{shot['suite']}-{shot['test']}"


def load_manifest(run_dir: Path) -> dict:
    return json.loads((run_dir / "manifest.json").read_text())


def crop_box(frame: dict, size: tuple[int, int], pad: int = 2):
    """Pixel box for a frame's normalised rect, padded and clamped. None if empty."""
    if frame.get("x") is None or frame.get("w") is None:
        return None
    W, H = size
    l = int(round(frame["x"] * W)) - pad
    t = int(round(frame["y"] * H)) - pad
    r = int(round((frame["x"] + frame["w"]) * W)) + pad
    b = int(round((frame["y"] + frame["h"]) * H)) + pad
    l, t, r, b = max(0, l), max(0, t), min(W, r), min(H, b)
    if r - l < 1 or b - t < 1:
        return None
    return (l, t, r, b)


def safe_name(s: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "_", s)


def compact(p: Path) -> str:
    home = str(Path.home())
    s = str(p)
    return "~" + s[len(home):] if s.startswith(home) else s


VENV_PYTHON = REPO / "tools" / ".venv" / "bin" / "python"


def need_pillow():
    """Pillow is a dev-tool dependency only. Re-run under tools/.venv if the
    current interpreter lacks it; say how to create the venv if that is missing."""
    try:
        import PIL  # noqa: F401
        return
    except ImportError:
        pass
    import sys
    # Compare prefixes, not resolved executables: a venv's python is a symlink
    # to the very interpreter that just failed to import Pillow.
    if VENV_PYTHON.exists() and Path(sys.prefix).resolve() != VENV_PYTHON.parent.parent.resolve():
        os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), *sys.argv])
    sys.exit("Pillow is needed: python3 -m venv tools/.venv && tools/.venv/bin/pip install Pillow")
