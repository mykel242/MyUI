#!/usr/bin/env python3
"""check_toc.py -- the shipped addons' .toc files load what is there.

For MyUI and MyUI_Test (the folders tools/release.sh zips):

- the .toc is named after its folder and has ## Interface, ## Title and
  ## Version lines;
- every file it lists exists, and every .lua/.xml in the folder is listed
  (an unlisted file never loads; a missing one is a load error in game).
  Bindings.xml is the exception: the client loads it by name;
- every .xml in the folder parses.

    tools/check_toc.py      exit 1 and list problems, or print "clean"

Standard library only (runs in CI's bookworm image).
"""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ADDONS = ("MyUI", "MyUI_Test")
REQUIRED = ("Interface", "Title", "Version")


def check(addon: str) -> list[str]:
    folder = REPO / addon
    toc = folder / f"{addon}.toc"
    if not toc.is_file():
        return [f"{addon}: no {toc.name}"]
    problems = []
    fields, listed = {}, []
    for line in toc.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("##"):
            key, _, value = line[2:].partition(":")
            fields[key.strip()] = value.strip()
        elif line and not line.startswith("#"):
            listed.append(line.replace("\\", "/"))
    for key in REQUIRED:
        if not fields.get(key):
            problems.append(f"{toc.name}: no ## {key}")
    for name in listed:
        if not (folder / name).is_file():
            problems.append(f"{toc.name}: lists {name}, which is not there")
    present = {p.relative_to(folder).as_posix() for p in folder.rglob("*")
               if p.suffix in (".lua", ".xml")}
    for name in sorted(present - set(listed) - {"Bindings.xml"}):
        problems.append(f"{toc.name}: {name} is not listed, so it never loads")
    for name in sorted(present):
        if name.endswith(".xml"):
            try:
                ET.parse(folder / name)
            except ET.ParseError as err:
                problems.append(f"{addon}/{name}: not well-formed ({err})")
    return problems


def main() -> int:
    problems = [p for addon in ADDONS for p in check(addon)]
    for p in problems:
        print(p)
    if not problems:
        print(f"clean -- {len(ADDONS)} toc(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
