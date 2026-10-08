#!/bin/zsh
# Cut a GitHub release for the current version in Info.plist.
#
# Run this on the maintainer's Mac (the one with the "Shelf Local Signing"
# certificate) so the published app is signed the same way as every other
# build and macOS keeps the Accessibility grant across updates. CI can't do
# this — it has no access to the signing key — which is why releases are
# published by hand.
#
# Prerequisites: gh (authenticated), a clean build, and the version already
# bumped in Info.plist (CFBundleShortVersionString + CFBundleVersion).
#
# Optional, with an Apple Developer ID (see docs/HANDOVER.md, "Developer ID and notarization"):
#   SHELF_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"  sign for distribution
#   SHELF_NOTARY_PROFILE=shelf-notary                              notarize and staple
# Without them the release is signed with Shelf Local Signing, as before.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
TAG="v$VERSION"
ZIP="dist/Shelf-$VERSION.zip"

echo "Preparing release $TAG"

# Build + package the signed, universal app into dist/.
./build.sh --package

if [ ! -f "$ZIP" ]; then
  echo "error: $ZIP was not produced by build.sh --package" >&2
  exit 1
fi

NOTES_GATEKEEPER="Because Shelf is signed with a self-signed certificate (not an Apple Developer ID), macOS will ask you to approve it once via System Settings → Privacy & Security → Open Anyway. See INSTALL.md for the steps."
if [ -n "${SHELF_NOTARY_PROFILE:-}" ]; then
  if [ -z "${SHELF_SIGN_IDENTITY:-}" ]; then
    echo "error: SHELF_NOTARY_PROFILE needs SHELF_SIGN_IDENTITY (a Developer ID Application identity)" >&2
    exit 1
  fi
  echo "Notarizing $ZIP (this can take a few minutes)"
  xcrun notarytool submit "$ZIP" --keychain-profile "$SHELF_NOTARY_PROFILE" --wait
  # Staple the ticket so Gatekeeper can verify the app offline, then re-zip the stapled app.
  xcrun stapler staple build/Shelf.app
  rm -f "$ZIP"
  ditto -c -k --keepParent build/Shelf.app "$ZIP"
  spctl --assess --type execute --verbose build/Shelf.app
  NOTES_GATEKEEPER="Shelf is signed with an Apple Developer ID and notarized, so it opens normally."
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "error: tag $TAG already exists — bump the version in Info.plist first" >&2
  exit 1
fi

git tag "$TAG"
git push origin "$TAG"

gh release create "$TAG" \
  "$ZIP" \
  docs/INSTALL.md \
  docs/USER_GUIDE.md \
  --title "Shelf $VERSION" \
  --notes "See INSTALL.md to install. Shelf is local-only: it never sends your clipboard anywhere.

$NOTES_GATEKEEPER"

echo "Published $TAG with $ZIP"
