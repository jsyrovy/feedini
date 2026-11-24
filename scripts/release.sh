#!/bin/bash
# Builds a Feedini release for distribution outside the App Store: archived, signed with Developer ID, notarized and
# stapled. Run it as `make release` on a clean commit tagged v<MARKETING_VERSION>; it changes nothing in git.
#
# Output in build/release: Feedini-<version>.zip (the app), its .sha256 and Feedini-<version>-dSYMs.zip.
# Needs the team's "Developer ID Application" identity in the keychain, its provisioning profile $PROFILE_NAME (with
# iCloud / CloudKit and push, for sync) installed, and notarytool credentials saved as the keychain profile
# $NOTARY_PROFILE (default "notary"). See "Releasing" in CLAUDE.md.

set -euo pipefail

TEAM_ID=DZ7S6R9RRN
NOTARY_PROFILE=${NOTARY_PROFILE:-notary}
PROFILE_NAME=${PROFILE_NAME:-Feedini Developer ID}

cd "$(dirname "$0")/.."

OUT=build/release
ARCHIVE=$OUT/Feedini.xcarchive
APP=$OUT/Feedini.app

fail() {
    echo "release: $*" >&2
    exit 1
}

step() {
    echo "==> $*"
}

# Without extended attributes: ditto would store them (the system's com.apple.provenance) as ._ files, which break the
# signature when the zip is unpacked by anything but ditto or Archive Utility.
pack() {
    ditto -c -k --norsrc --noextattr --noacl --keepParent "$1" "$2"
}

# Checks first, so nothing is built (or sent to Apple) for a release that would be refused anyway.

[[ -z "$(git status --porcelain)" ]] || fail "the working tree is not clean"

settings=$(xcodebuild -project Feedini.xcodeproj -target Feedini -configuration Release -showBuildSettings -json 2>/dev/null)
VERSION=$(plutil -extract 0.buildSettings.MARKETING_VERSION raw -o - - <<<"$settings")
[[ $VERSION =~ ^[0-9]+\.[0-9]+$ ]] || fail "MARKETING_VERSION '$VERSION' is not major.minor"
TAG=v$VERSION
BUILD=$(git rev-list --count HEAD)
ZIP=$OUT/Feedini-$VERSION.zip

[[ $(git rev-parse -q --verify "refs/tags/$TAG^{commit}") == "$(git rev-parse HEAD)" ]] \
    || fail "HEAD is not tagged $TAG"
grep -Eq "^## ${VERSION//./\\.} – [0-9]{4}-[0-9]{2}-[0-9]{2}$" CHANGELOG.md \
    || fail "CHANGELOG.md has no section '## $VERSION – <date>'"

identities=$(security find-identity -v -p codesigning)
grep -q "\"Developer ID Application: .* ($TEAM_ID)\"" <<<"$identities" \
    || fail "no Developer ID Application identity of team $TEAM_ID in the keychain"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null \
    || fail "notarytool can't use the keychain profile '$NOTARY_PROFILE'"

# The installed Developer ID profile of the app with CloudKit (Xcode looks in both folders).
profile_ok=false
for file in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.provisionprofile \
    "$HOME/Library/MobileDevice/Provisioning Profiles"/*.provisionprofile; do
    [[ -f $file ]] || continue
    plist=$(security cms -D -i "$file" 2>/dev/null) || continue
    [[ $(plutil -extract Name raw -o - - <<<"$plist" 2>/dev/null) == "$PROFILE_NAME" ]] || continue
    [[ $(plutil -extract 'Entitlements.com\.apple\.application-identifier' raw -o - - <<<"$plist") == \
        "$TEAM_ID.cz.jsyrovy.feedini" ]] || continue
    expiry=$(plutil -extract ExpirationDate raw -o - - <<<"$plist")
    [[ $(date -u +%Y-%m-%dT%H:%M:%SZ) < $expiry ]] || fail "the profile '$PROFILE_NAME' expired on $expiry"
    plutil -extract 'Entitlements.com\.apple\.developer\.icloud-container-identifiers' json -o - - <<<"$plist" \
        | grep -q 'iCloud.cz.jsyrovy.feedini' || continue
    profile_ok=true
done
$profile_ok || fail "no installed provisioning profile '$PROFILE_NAME' of the app with its iCloud container"

step "Feedini $VERSION ($BUILD) from $TAG ($(git rev-parse --short HEAD))"
rm -rf "$OUT"
mkdir -p "$OUT"

# A clean universal build (generic destination), signed for distribution right away, so the app is taken from the
# archive as it is.
step "Archiving"
xcodebuild -project Feedini.xcodeproj -scheme Feedini -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$OUT/DerivedData" -archivePath "$ARCHIVE" -quiet archive \
    CURRENT_PROJECT_VERSION="$BUILD" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="$TEAM_ID" PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME" FEEDINI_APS_ENVIRONMENT=production \
    OTHER_CODE_SIGN_FLAGS=--timestamp
rm -rf "$OUT/DerivedData"
ditto "$ARCHIVE/Products/Applications/Feedini.app" "$APP"

# Problems that notarization would report only after a round trip of minutes (or, for a missing architecture, not at
# all).
step "Checking the signature"
codesign --verify --deep --strict "$APP"
signature=$(codesign -dvv "$APP" 2>&1)
grep -q "^Authority=Developer ID Application: .* ($TEAM_ID)$" <<<"$signature" || fail "not signed with Developer ID"
grep -q "^CodeDirectory .*flags=.*runtime" <<<"$signature" || fail "the hardened runtime is off"
grep -q "^Timestamp=" <<<"$signature" || fail "the signature has no secure timestamp"
entitlements=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -convert json -o - -)
for expected in '"com.apple.developer.icloud-container-environment":"Production"' \
    '"com.apple.developer.aps-environment":"production"' '"com.apple.developer.icloud-services":["CloudKit"]'; do
    [[ $entitlements == *"$expected"* ]] || fail "the entitlements lack $expected: $entitlements"
done
[[ $entitlements != *get-task-allow* ]] || fail "the app can be debugged (get-task-allow)"
archs=$(lipo -archs "$APP/Contents/MacOS/Feedini")
[[ $archs == *arm64* && $archs == *x86_64* ]] || fail "not a universal binary: $archs"

step "Notarizing (usually a few minutes)"
pack "$APP" "$OUT/notarize.zip"
# notarytool may exit non-zero for a rejected submission; its JSON says what happened either way.
result=$(xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait \
    --output-format json) || true
status=$(plutil -extract status raw -o - - <<<"$result" 2>/dev/null) || fail "notarytool submit failed: $result"
if [[ $status != Accepted ]]; then
    id=$(plutil -extract id raw -o - - <<<"$result")
    xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    fail "notarization ended with '$status' (submission $id)"
fi
rm "$OUT/notarize.zip"

step "Stapling"
xcrun stapler staple -q "$APP"
xcrun stapler validate -q "$APP"

step "Packaging"
pack "$APP" "$ZIP"
pack "$ARCHIVE/dSYMs/Feedini.app.dSYM" "$OUT/Feedini-$VERSION-dSYMs.zip"
(cd "$OUT" && shasum -a 256 "Feedini-$VERSION.zip" >"Feedini-$VERSION.zip.sha256")

# The zip as a user gets it: unpacked by a plain unzip and judged the way macOS judges an app before running it.
step "Checking the zip as a download"
download=$(mktemp -d)
trap 'rm -rf "$download"' EXIT
unzip -q "$ZIP" -d "$download"
syspolicy_check distribution "$download/Feedini.app"

step "Done: Feedini $VERSION ($BUILD)"
ls -l "$OUT"/Feedini-"$VERSION"*
echo "Next: git push origin main $TAG, then make publish"
