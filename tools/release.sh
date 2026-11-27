#!/usr/bin/env bash
# MyUI :: tools/release.sh
# Builds MyUI and MyUI_Test as zips and publishes them as a Forgejo release,
# for InterWoven to install (interwoven docs/handoff-addon-releases.md).
#
#   tools/release.sh             build, then create the release and upload
#   tools/release.sh --dry-run   build into dist/ only; nothing leaves the Mac
#
# On a tag vX.Y.Z: a release, version X.Y.Z. Anywhere else: a prerelease
# named by `git describe --tags --long` (never tagged by hand). The newest
# PRERELEASES_KEPT prereleases are kept; releases are never deleted.
#
# The write token comes from $FORGEJO_TOKEN or the file $FORGEJO_TOKEN_FILE
# (default ~/.config/forgejo/token). It is never printed, and never put on a
# command line: curl reads the header from a private temp file.

set -euo pipefail

HOST="https://git.jurassicfrog.com"
REPO="mykel/MyUI"
ADDONS=(MyUI MyUI_Test)
PRERELEASES_KEPT=10

DRY=0
case "${1:-}" in
    --dry-run) DRY=1 ;;
    "") ;;
    *) echo "usage: tools/release.sh [--dry-run]" >&2; exit 2 ;;
esac

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# 1. Every build names a commit.
if [ -n "$(git status --porcelain)" ]; then
    echo "release: the tree has uncommitted changes; commit or stash first" >&2
    exit 1
fi
SHA="$(git rev-parse HEAD)"

# 2. The version, from git.
if EXACT="$(git describe --exact-match --tags HEAD 2>/dev/null)" \
        && [[ "$EXACT" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    TAG="$EXACT"; PRERELEASE=false
else
    TAG="$(git describe --tags --long)"; PRERELEASE=true
fi
VERSION="${TAG#v}"

# 3. The zips: each addon folder at the top, its .toc stamped.
DIST="$ROOT/dist"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$DIST"
ZIPS=()
for addon in "${ADDONS[@]}"; do
    dir="$STAGE/$addon"
    mkdir -p "$dir"
    # export-ignore in .gitattributes is honoured by git archive.
    git archive --format=tar HEAD "$addon" | tar -x -C "$dir"
    toc="$dir/$addon/$addon.toc"
    [ -f "$toc" ] || { echo "release: $addon has no $addon.toc" >&2; exit 1; }
    sed -i.bak -E "s/^## Version:.*/## Version: $VERSION/" "$toc" && rm -f "$toc.bak"
    zip="$DIST/$addon-$VERSION.zip"
    rm -f "$zip"
    (cd "$dir" && zip -qrX "$zip" "$addon")
    ZIPS+=("$zip")
done

echo "version  $VERSION ($([ "$PRERELEASE" = true ] && echo prerelease || echo release))"
echo "commit   $SHA"
for z in "${ZIPS[@]}"; do echo "built    ${z#$ROOT/}"; done

if [ "$DRY" = 1 ]; then
    echo "dry run: nothing uploaded"
    exit 0
fi

# 4. The release, and its zips.
TOKEN="${FORGEJO_TOKEN:-}"
if [ -z "$TOKEN" ]; then
    f="${FORGEJO_TOKEN_FILE:-$HOME/.config/forgejo/token}"
    [ -r "$f" ] || { echo "release: no token (set FORGEJO_TOKEN or put it in $f)" >&2; exit 1; }
    TOKEN="$(tr -d '[:space:]' < "$f")"
fi
HDR="$STAGE/auth"
( umask 077; printf 'Authorization: token %s\n' "$TOKEN" > "$HDR" )
unset TOKEN
API="$HOST/api/v1/repos/$REPO"

body="$(jq -n --arg t "$TAG" --arg c "$SHA" --arg n "$VERSION" --argjson p "$PRERELEASE" \
    '{tag_name:$t, target_commitish:$c, name:$n, prerelease:$p}')"
resp="$(curl -sS --fail-with-body -X POST -H @"$HDR" -H "Content-Type: application/json" \
    "$API/releases" -d "$body")" || { echo "release: create failed: $resp" >&2; exit 1; }
ID="$(jq -r '.id' <<<"$resp")"
echo "release  $HOST/$REPO/releases/tag/$TAG (id $ID)"

for z in "${ZIPS[@]}"; do
    name="$(basename "$z")"
    curl -sS --fail-with-body -X POST -H @"$HDR" \
        -F "attachment=@$z" "$API/releases/$ID/assets?name=$name" > /dev/null \
        || { echo "release: upload of $name failed" >&2; exit 1; }
    echo "uploaded $name"
done

# 5. Keep the newest prereleases; the older ones go, with the tags they made.
if [ "$PRERELEASE" = true ]; then
    old="$(curl -sS --fail-with-body -H @"$HDR" "$API/releases?limit=50" \
        | jq -r --argjson k "$PRERELEASES_KEPT" \
            '[.[] | select(.prerelease)] | sort_by(.created_at) | reverse | .[$k:] | .[] | "\(.id) \(.tag_name)"')"
    while read -r id tag; do
        [ -n "$id" ] || continue
        curl -sS --fail-with-body -X DELETE -H @"$HDR" "$API/releases/$id" > /dev/null
        curl -sS -X DELETE -H @"$HDR" "$API/tags/$tag" > /dev/null || true
        echo "pruned   $tag"
    done <<<"$old"
fi
