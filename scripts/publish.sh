#!/bin/bash
# Uploads the release built by `make release` (build/release) as a draft GitHub release of its tag, with its
# CHANGELOG.md section as the notes. Run it as `make publish` after `git push origin main v<version>`, then check the
# draft on GitHub and publish it there (or `gh release edit v<version> --draft=false`). Needs `gh`, logged in.

set -euo pipefail

cd "$(dirname "$0")/.."

OUT=build/release

fail() {
    echo "publish: $*" >&2
    exit 1
}

# The release in build/release (make release leaves exactly one) decides the version.
checksums=("$OUT"/Feedini-*.zip.sha256)
[[ ${#checksums[@]} -eq 1 && -f ${checksums[0]} ]] || fail "no release in $OUT (make release)"
VERSION=${checksums[0]#"$OUT/Feedini-"}
VERSION=${VERSION%.zip.sha256}
TAG=v$VERSION
ZIP=$OUT/Feedini-$VERSION.zip
DSYMS=$OUT/Feedini-$VERSION-dSYMs.zip

[[ -f $ZIP && -f $DSYMS ]] || fail "$OUT is incomplete (make release)"
(cd "$OUT" && shasum -a 256 -s -c "Feedini-$VERSION.zip.sha256") || fail "$ZIP doesn't match its checksum"

commit=$(git rev-parse -q --verify "refs/tags/$TAG^{commit}") || fail "there is no tag $TAG"
build=$(unzip -p "$ZIP" Feedini.app/Contents/Info.plist | plutil -extract CFBundleVersion raw -o - -)
[[ $build == "$(git rev-list --count "$commit")" ]] || fail "$ZIP was not built from $TAG (make release)"
remote=$(git ls-remote origin "refs/tags/$TAG")
[[ ${remote%%[[:space:]]*} == "$(git rev-parse "refs/tags/$TAG")" ]] \
    || fail "$TAG is not on GitHub as it is here (git push origin main $TAG)"

gh auth status >/dev/null 2>&1 || fail "gh is not logged in (gh auth login)"
! gh release view "$TAG" >/dev/null 2>&1 || fail "GitHub already has a release $TAG"

# The section of the tagged CHANGELOG.md, without its heading and leading blank lines.
notes=$(git show "$commit:CHANGELOG.md" \
    | awk -v heading="## $VERSION " 'index($0, heading) == 1 { f = 1; next } /^## / { f = 0 } f' | sed '/./,$!d')
[[ -n $notes ]] || fail "CHANGELOG.md of $TAG has no notes for $VERSION"

url=$(gh release create "$TAG" "$ZIP" "$ZIP.sha256" "$DSYMS" --verify-tag --draft --title "Feedini $VERSION" \
    --notes "$notes")
echo "Draft: $url"
echo "Publish it on GitHub, or: gh release edit $TAG --draft=false"
