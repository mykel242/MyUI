#!/usr/bin/env python3
"""check_deps.py -- one job: fail on any dependency outside MyUI and Blizzard.

RULES.md: MyUI depends on itself and Blizzard, nothing else. Checks every .toc
in the repo for Dependencies / RequiredDeps / Dep* / OptionalDeps / LoadWith /
X-Embeds naming anything that is neither an addon in this repo nor a Blizzard_
addon, and every .lua for LibStub, the usual way a library sneaks in.

    tools/check_deps.py          exit 1 and list offenders, or print "clean"
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SKIP = {"reference", "design", ".git", ".venv", "shots", "test"}
FIELD = re.compile(r"^##\s*(Dependencies|RequiredDeps|Dep[A-Za-z0-9]*|OptionalDeps|LoadWith|X-Embeds)\s*:\s*(.*)$",
                   re.I)


def addon_files(pattern: str) -> list[Path]:
    return [p for p in REPO.rglob(pattern) if not (set(p.relative_to(REPO).parts) & SKIP)]


def main() -> int:
    tocs = addon_files("*.toc")
    ours = {t.stem for t in tocs}
    problems = []
    for toc in tocs:
        for n, line in enumerate(toc.read_text(errors="replace").splitlines(), 1):
            m = FIELD.match(line.strip())
            if not m:
                continue
            for dep in (d.strip() for d in m.group(2).split(",")):
                if dep and dep not in ours and not dep.startswith("Blizzard_"):
                    problems.append(f"{toc.relative_to(REPO)}:{n}: {m.group(1)} names {dep!r}")
    for lua in addon_files("*.lua"):
        for n, line in enumerate(lua.read_text(errors="replace").splitlines(), 1):
            code = line.split("--", 1)[0]
            if "LibStub" in code:
                problems.append(f"{lua.relative_to(REPO)}:{n}: LibStub")
    if problems:
        print("dependencies outside MyUI and Blizzard:")
        for p in problems:
            print("  " + p)
        return 1
    print(f"clean -- {len(tocs)} toc(s): {', '.join(sorted(ours))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
