#!/bin/zsh
# Cut a GitHub release for the current version in Info.plist.
#
# Run this on the maintainer's Mac: it needs the signing identity and, for notarization, the
# notarytool credentials, neither of which CI has.
#
# Prerequisites: gh (authenticated), a clean build, and the version already
# bumped in Info.plist (CFBundleShortVersionString + CFBundleVersion).
#
# When build.sh signs with a Developer ID (found in the keychain, or SHELF_SIGN_IDENTITY), the release
# is notarized with the notarytool profile SHELF_NOTARY_PROFILE (default "shelf-notary"); see
# docs/HANDOVER.md, "Code signing". Without a Developer ID it is signed with Shelf Local Signing.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
TAG="v$VERSION"
ZIP="dist/Shelf-$VERSION.zip"

echo "Preparing release $TAG"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "error: tag $TAG already exists — bump the version in Info.plist first" >&2
  exit 1
fi

# Build + package the signed, universal app into dist/.
./build.sh --package

if [ ! -f "$ZIP" ]; then
  echo "error: $ZIP was not produced by build.sh --package" >&2
  exit 1
fi

NOTES_GATEKEEPER="Because Shelf is signed with a self-signed certificate (not an Apple Developer ID), macOS will ask you to approve it once via System Settings → Privacy & Security → Open Anyway. See INSTALL.md for the steps."
# Capture first: piping into grep -q would let codesign die of SIGPIPE, which pipefail treats as failure.
SIGNATURE=$(codesign -dv --verbose=2 build/Shelf.app 2>&1)
if [[ "$SIGNATURE" == *"Authority=Developer ID Application"* ]]; then
  PROFILE="${SHELF_NOTARY_PROFILE:-shelf-notary}"
  echo "Notarizing $ZIP with profile $PROFILE (this can take a few minutes)"
  # --wait exits 0 even when Apple rejects the upload, so check the status explicitly.
  RESULT=$(xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait)
  echo "$RESULT"
  if [[ "$RESULT" != *"status: Accepted"* ]]; then
    echo "error: notarization was not accepted; see: xcrun notarytool log <id> --keychain-profile $PROFILE" >&2
    exit 1
  fi
  # Staple the ticket so Gatekeeper can verify the app offline, then re-zip the stapled app.
  xcrun stapler staple build/Shelf.app
  rm -f "$ZIP"
  ditto -c -k --keepParent build/Shelf.app "$ZIP"
  spctl --assess --type execute --verbose build/Shelf.app
  NOTES_GATEKEEPER="Shelf is signed with an Apple Developer ID and notarized, so it opens normally."
fi


# This version's section of CHANGELOG.md (between its heading and the next one), for the release notes.
CHANGES=$(awk -v v="$VERSION" '
  index($0, "## [" v "]") == 1 { on = 1; next }
  on && /^## \[/ { exit }
  on { print }' CHANGELOG.md)

git tag "$TAG"
git push origin "$TAG"

gh release create "$TAG" \
  "$ZIP" \
  docs/INSTALL.md \
  docs/USER_GUIDE.md \
  --title "Shelf $VERSION" \
  --notes "$CHANGES

See INSTALL.md to install. Shelf is local-only: it never sends your clipboard anywhere.

$NOTES_GATEKEEPER"

echo "Published $TAG with $ZIP"
