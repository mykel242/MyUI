#!/usr/bin/env bash
# Everything that can be checked without the game client.
# RULES.md: run this at the end of every phase. A phase is not done until it
# is clean.

set -uo pipefail
cd "$(dirname "$0")"

fail=0
run() {
    echo
    echo "--- $1"
    shift
    if "$@"; then
        echo "    pass"
    else
        echo "    FAIL"
        fail=1
    fi
}

lua=""
for candidate in luajit lua5.1 lua; do
    if command -v "$candidate" >/dev/null 2>&1; then lua="$candidate"; break; fi
done

if [ -z "$lua" ]; then
    echo "no Lua interpreter found -- install luajit to run the addon tests"
    fail=1
else
    run "addon tests ($lua)" bash -c "cd test && $lua run_tests.lua >/dev/null"
fi

# A real parser, not a grep. Bindings.xml shipped "not well-formed" once, from
# a double hyphen inside a comment -- legal as an em dash in every Lua file here
# and illegal in XML -- and the client's only complaint was one LUA_WARNING
# while every binding silently stopped registering. Nothing else reads this file.
run "bindings xml"         python3 -c "import xml.etree.ElementTree as ET; ET.parse('MyUI/Bindings.xml')"
run "compliance lint"      python3 rules_lint.py
run "lint self-test"       bash -c "python3 test/test_lint.py >/dev/null"

echo
if [ "$fail" -eq 0 ]; then
    echo "all clean"
else
    echo "something failed -- rerun the failing suite on its own for detail"
fi
exit "$fail"
