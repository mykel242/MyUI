#!/usr/bin/env python3
"""Proves rules_lint.py catches what it claims to.

Run from the project root:  python3 test/test_lint.py
"""

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "test" / "fixtures" / "violations.lua"

checks = failures = 0


def check(name, cond, detail=None):
    global checks, failures
    checks += 1
    if cond:
        print(f"  ok   {name}")
    else:
        failures += 1
        print(f"  FAIL {name}" + (f"  -- {detail}" if detail else ""))


def run(target):
    proc = subprocess.run(
        [sys.executable, str(ROOT / "rules_lint.py"), str(target)],
        capture_output=True, text=True,
    )
    return proc.returncode, proc.stdout


print("== rules_lint against the violation fixture")
code, out = run(FIXTURE)
check("exits non-zero on findings", code == 1, code)

for rule, line in [
    ("R1", 12), ("R2", 17), ("R3", 24), ("R4", 29),
    ("R5", 36), ("R6", 41), ("R7", 47),
]:
    hits = [l for l in out.splitlines() if f":{line}: {rule}" in l]
    check(f"{rule} fires at line {line}", len(hits) == 1,
          f"{len(hits)} hits")

check("the annotated line is not reported", ":53:" not in out)
check("a string literal does not trip R3", ":56:" not in out)
check("naming OnUpdate in a string is not registering one", ":59:" not in out)
check("prose in comments does not trip anything",
      not any(f":{n}:" in out for n in (1, 2, 3, 4, 5, 6)))
check("R7 fires twice in total -- once per forwarded call",
      out.count("R7 ") == 2, out.count("R7 "))

print("")
print("== rules_lint against the addon")
code, out = run(ROOT / "MyUI")
check("the shipped addon is clean", code == 0, out.strip()[:200])
check("  and says so", "0 violations" in out)

print("")
print(f"{checks} checks, {failures} failures")
sys.exit(0 if failures == 0 else 1)
