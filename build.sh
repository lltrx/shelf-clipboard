#!/bin/zsh
# Build Shelf.app (universal: Apple Silicon + Intel).
#   ./build.sh            build only, into build/Shelf.app
#   ./build.sh --install  build, install to ~/Applications and launch
#   ./build.sh --package  build and zip into dist/ for sharing with other people
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64
swift build -c release --arch x86_64

APP=build/Shelf.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create .build/arm64-apple-macosx/release/Shelf .build/x86_64-apple-macosx/release/Shelf \
  -output "$APP/Contents/MacOS/Shelf"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# A stable local identity keeps the Accessibility grant across rebuilds; fall back to ad-hoc.
if security find-identity -p codesigning | grep -q "Shelf Local Signing"; then
  codesign --force --sign "Shelf Local Signing" "$APP"
else
  codesign --force --sign - "$APP"
fi

case "${1:-}" in
  --install)
    pkill -x Shelf 2>/dev/null || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/Shelf.app
    cp -R "$APP" ~/Applications/Shelf.app
    open ~/Applications/Shelf.app
    echo "Installed and launched ~/Applications/Shelf.app"
    ;;
  --package)
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
    mkdir -p dist
    ZIP="dist/Shelf-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    cp docs/INSTALL.md docs/USER_GUIDE.md dist/
    echo "Packaged $ZIP (share it with dist/INSTALL.md and dist/USER_GUIDE.md)"
    ;;
  *)
    echo "Built $APP (run ./build.sh --install to install, --package to share)"
    ;;
esac
