#!/usr/bin/env python3
"""Static half of the compliance harness.

Guard.lua catches a violation when the line runs. This catches the ones that
never run on a target dummy -- which is the failure mode RULES.md is actually
worried about.

PLAN.md's Phase 4 acceptance says "grep the diff for arithmetic on any unit
value -- there must be none." This is that grep, made repeatable.

    python3 rules_lint.py                # lint MyUI/
    python3 rules_lint.py path/to/file.lua

Comments and string literals are stripped before matching, so a rule can be
discussed in prose without tripping itself. To allow a real line, annotate it:

    local pct = UnitHealth("player")   -- lint:allow R6 forwarded, never read

Standard library only. No pip, no venv.
"""

import re
import sys
from pathlib import Path

# --------------------------------------------------------------------------
# APIs that return a secret on 12.1. Citations in API-NOTES-12.1.md.
# --------------------------------------------------------------------------
SECRET_APIS = [
    "UnitHealth", "UnitHealthMax", "UnitHealthMissing", "UnitHealthPercent",
    "UnitPower", "UnitPowerMax", "UnitPowerPercent",
    "UnitCastingInfo", "UnitChannelInfo",
    "UnitThreatSituation", "UnitDetailedThreatSituation",
    "GetSpellCooldown", "GetSpellCharges",
]
SECRET_RE = re.compile(r"\b(" + "|".join(SECRET_APIS) + r")\s*\(")

# Setters that are AllowedWhenUntainted -- they refuse a forwarded secret.
REFUSED_SINKS = re.compile(r"[:.](SetScale|SetColorFill)\s*\(")

ARITH = re.compile(r"[-+*/%^]|\.\.")
COMPARE = re.compile(r"[<>]=?|==|~=")

# OnUpdate is legal only in the reveal engine's cursor and peek paths
# (RULES.md). Everything else must be event-driven.
#
# Match the registration, not the word: Rules.lua quotes the prohibition in
# prose, and a lint that trips on its own rulebook trains you to ignore it.
ONUPDATE_RE = re.compile(r"""(SetScript|HookScript)\s*\(\s*["']OnUpdate["']""")
ONUPDATE_ALLOWED = {"Reveal.lua", "Peek.lua"}

RULES_POINTER = "RULES.md -- forwarding a secret is legal, inspecting one is not"


def strip_lua(src, keep_strings=False):
    """Blank out comments -- and string literals unless keep_strings.

    Two passes are needed. Most rules must not fire on prose or on a name
    mentioned in a literal, so they read the fully stripped text. R5 is the
    exception: "OnUpdate" only ever appears AS a string literal, so stripping
    strings would make that rule permanently silent -- which is exactly how it
    failed the first time it was tested.
    """
    out = []
    i, n = 0, len(src)
    while i < n:
        ch = src[i]

        # Long bracket, as a comment or a string: [[ ]], [=[ ]=], --[[ ]]
        m = re.match(r"(--)?\[(=*)\[", src[i:])
        if m:
            eq = m.group(2)
            close = "]" + eq + "]"
            end = src.find(close, i + m.end())
            end = n if end == -1 else end + len(close)
            out.append("".join(c if c == "\n" else " " for c in src[i:end]))
            i = end
            continue

        if src.startswith("--", i):
            end = src.find("\n", i)
            end = n if end == -1 else end
            out.append(" " * (end - i))
            i = end
            continue

        if ch in "\"'":
            j = i + 1
            while j < n and src[j] != ch:
                j += 2 if src[j] == "\\" else 1
            j = min(j + 1, n)
            chunk = src[i:j]
            out.append(chunk if keep_strings
                       else "".join(c if c == "\n" else " " for c in chunk))
            i = j
            continue

        out.append(ch)
        i += 1
    return "".join(out)


def check_file(path):
    raw = path.read_text(encoding="utf-8")
    raw_lines = raw.splitlines()
    code_lines = strip_lua(raw).splitlines()
    # Comments gone, strings kept -- see strip_lua.
    literal_lines = strip_lua(raw, keep_strings=True).splitlines()
    findings = []

    def report(lineno, rule, message):
        original = raw_lines[lineno - 1] if lineno <= len(raw_lines) else ""
        allow = re.search(r"--\s*lint:allow\s+(\S+)", original)
        if allow and allow.group(1) == rule:
            return
        findings.append((path, lineno, rule, message, original.strip()))

    for num, line in enumerate(code_lines, 1):
        secret = SECRET_RE.search(line)

        if secret:
            call_tail = line[secret.end():]
            if ARITH.search(call_tail) or ARITH.search(line[:secret.start()]):
                report(num, "R1", f"arithmetic on the result of {secret.group(1)}()")
            if COMPARE.search(line):
                report(num, "R2", f"comparison involving {secret.group(1)}() -- "
                                  "no threshold branches")
            if re.search(r"\blocal\s+[\w,\s]+=\s*[^=]*" + re.escape(secret.group(1)), line):
                report(num, "R6", f"capturing {secret.group(1)}() into a local. "
                                  "Forward it straight into the setter instead")
            if "Guard.Send" not in line and re.search(r"[:.]Set\w+\s*\(", line):
                report(num, "R7", f"{secret.group(1)}() forwarded outside Guard.Send")

        sink = REFUSED_SINKS.search(line)
        if sink:
            report(num, "R3", f"{sink.group(1)} is AllowedWhenUntainted and will "
                              "refuse a forwarded secret (API-NOTES-12.1.md 2)")

        if "HasSecretValues" in line and re.search(r"\b(if|while|and|or|not)\b", line):
            report(num, "R4", "HasSecretValues is a crash guard, not a signal. "
                              "Never branch appearance on it")

        literal = literal_lines[num - 1] if num <= len(literal_lines) else ""
        if ONUPDATE_RE.search(literal) and path.name not in ONUPDATE_ALLOWED:
            report(num, "R5", f"OnUpdate in {path.name}. Legal only for cursor "
                              "proximity and the peek timer")

    return findings


def main(argv):
    targets = []
    for arg in argv[1:]:
        p = Path(arg)
        targets.extend(sorted(p.rglob("*.lua")) if p.is_dir() else [p])
    if not targets:
        root = Path(__file__).parent / "MyUI"
        targets = sorted(root.rglob("*.lua"))

    if not targets:
        print("nothing to lint")
        return 0

    findings = []
    for path in targets:
        findings.extend(check_file(path))

    if not findings:
        print(f"clean -- {len(targets)} file(s), 0 violations")
        return 0

    for path, lineno, rule, message, source in findings:
        print(f"{path}:{lineno}: {rule} {message}")
        print(f"    {source}")
    print(f"\n{len(findings)} violation(s) in {len(targets)} file(s)")
    print(RULES_POINTER)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
