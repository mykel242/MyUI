#!/usr/bin/env bash
# MyUI :: tools/ci.sh
# The checks CI runs (.forgejo/workflows/release.yml), runnable anywhere with
# git, zip and python3: no Lua needed (smoke.sh runs the Lua tests locally).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
step() { echo; echo "--- $1"; shift; "$@"; }
step "compliance lint"  python3 rules_lint.py MyUI MyUI_Test
step "lint self-test"   bash -c "python3 test/test_lint.py > /dev/null"
step "toc files"        python3 tools/check_toc.py
step "dependencies"     python3 tools/check_deps.py
step "both zips (dry run)" tools/release.sh --dry-run
echo; echo "ci: all clean"
