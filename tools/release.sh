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
# Needs git, curl, zip and python3 (the CI image has no jq).
#
# The write token comes from $FORGEJO_TOKEN (CI: the RELEASE_TOKEN secret) or
# the file $FORGEJO_TOKEN_FILE
# (default ~/.config/forgejo/release-token). It is never printed, and never put on a
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
# A prerelease's tag (vX.Y.Z-N-gSHA) is never a base for the next one's name.
EXACT="$(git tag --points-at HEAD | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)"
if [ -n "$EXACT" ]; then
    TAG="$EXACT"; PRERELEASE=false
else
    TAG="$(git describe --tags --long --exclude 'v*-[0-9]*-g[0-9a-f]*')"; PRERELEASE=true
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
    f="${FORGEJO_TOKEN_FILE:-$HOME/.config/forgejo/release-token}"
    [ -r "$f" ] || { echo "release: no token (set FORGEJO_TOKEN or put it in $f)" >&2; exit 1; }
    TOKEN="$(tr -d '[:space:]' < "$f")"
fi
HDR="$STAGE/auth"
( umask 077; printf 'Authorization: token %s\n' "$TOKEN" > "$HDR" )

# The tag goes up with git itself. Over HTTPS with the token in CI (passed
# through git's environment config, never on a command line); by hand, to
# origin with the usual credentials.
push_tag() {
    if [ -n "${FORGEJO_TOKEN:-}" ]; then
        GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraHeader \
            GIT_CONFIG_VALUE_0="Authorization: token $FORGEJO_TOKEN" \
            git push -q "$HOST/$REPO.git" "refs/tags/$1"
    else
        git push -q origin "refs/tags/$1"
    fi
}
unset TOKEN
API="$HOST/api/v1/repos/$REPO"
json() { python3 -c "import json,sys; d=json.load(sys.stdin); $1"; }

# Already made (the tag's run and main's run on the same commit, or a rerun):
# nothing to do.
code="$(curl -sS -o /dev/null -w '%{http_code}' -H @"$HDR" "$API/releases/tags/$TAG")"
if [ "$code" = 200 ]; then
    echo "release  $TAG exists already; nothing to do"
    exit 0
fi

body="$(TAG="$TAG" SHA="$SHA" VERSION="$VERSION" PRE="$PRERELEASE" python3 -c '
import json, os
print(json.dumps({"tag_name": os.environ["TAG"], "target_commitish": os.environ["SHA"],
                  "name": os.environ["VERSION"], "prerelease": os.environ["PRE"] == "true"}))')"
# The tag first. Forgejo 7.0 makes a release on a tag that does not exist
# yet without making the tag, and dates that release 1970-01-01: it then
# sorts below every other release (InterWoven never sees it as newest, and
# pruning by created_at deletes the wrong ones).
code="$(curl -sS -o /dev/null -w '%{http_code}' -H @"$HDR" "$API/tags/$TAG")"
if [ "$code" != 200 ]; then
    # Not POST /tags: on 2026-11-27 that left a release row with no git tag
    # behind it, and the name could not be used again.
    git tag -f "$TAG" "$SHA" > /dev/null
    push_tag "$TAG" || { echo "release: tag $TAG not pushed" >&2; exit 1; }
    echo "tagged   $TAG at ${SHA:0:7}"
fi

resp="$(curl -sS --fail-with-body -X POST -H @"$HDR" -H "Content-Type: application/json" \
    "$API/releases" -d "$body")" || { echo "release: create failed: $resp" >&2; exit 1; }
ID="$(json 'print(d["id"])' <<<"$resp")"
echo "release  $HOST/$REPO/releases/tag/$TAG (id $ID)"

# Confirm what Forgejo made: the tag is there, on this commit, and the
# release has a real date.
got="$(curl -sS --fail-with-body -H @"$HDR" "$API/tags/$TAG" | json 'print(d["commit"]["sha"])')" \
    || { echo "release: FAILED -- release $ID has no tag $TAG" >&2; exit 1; }
[ "$got" = "$SHA" ] || { echo "release: FAILED -- tag $TAG is on $got, not $SHA" >&2; exit 1; }
made="$(curl -sS --fail-with-body -H @"$HDR" "$API/releases/$ID" | json 'print(d["created_at"])')"
case "$made" in
    1970*|"") echo "release: FAILED -- release $ID is dated '$made'" >&2; exit 1 ;;
esac
echo "dated    $made"

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
        | json "
pre = sorted((r for r in d if r['prerelease']), key=lambda r: r['created_at'], reverse=True)
for r in pre[$PRERELEASES_KEPT:]: print(r['id'], r['tag_name'])")"
    while read -r id tag; do
        [ -n "$id" ] || continue
        curl -sS --fail-with-body -X DELETE -H @"$HDR" "$API/releases/$id" > /dev/null
        curl -sS -X DELETE -H @"$HDR" "$API/tags/$tag" > /dev/null || true
        echo "pruned   $tag"
    done <<<"$old"
fi
