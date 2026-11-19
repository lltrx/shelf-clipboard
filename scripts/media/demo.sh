#!/bin/bash
# Helpers for capturing Shelf's README screenshots and demo GIF on a Mac. The runbook is
# scripts/media/README.md. Every command is one call, so it works from any shell or agent.
#
#   demo.sh sandbox-on            move your history and settings aside; Shelf starts empty
#   demo.sh sandbox-off           put them back (always run this at the end)
#   demo.sh status                is the sandbox on? is Shelf running?
#   demo.sh copy-demo [items]     put the demo content on the clipboard (see demo-content.swift)
#   demo.sh press COMBO           a key with modifiers, by physical key: cmd+shift+v, return, esc,
#                                 tab, shift+tab, space, left, right, up, down, opt+right, a, 1, ...
#   demo.sh type TEXT             type text (switch the input source to ABC or U.S. first)
#   demo.sh screen                the main screen's frame and visible frame
#   demo.sh windows [App]         an app's windows (default Shelf): id, x,y,w,h, layer, title
#   demo.sh shot-window ID FILE   one window, no shadow
#   demo.sh shot-rect X,Y,W,H FILE
#   demo.sh click X Y | drag X1 Y1 X2 Y2
#   demo.sh record X,Y,W,H SECONDS FILE.mov   (run it in the background, then drive the demo)
#   demo.sh gif IN.mov OUT.gif [WIDTH] [FPS]
#   demo.sh shrink FILE.png...    at most 2000 px wide, then pngquant if it's installed
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BIN=/tmp/shelf-media-bin
BUNDLE=com.turkifaisal.shelf
DATA="$HOME/Library/Application Support/Shelf"
SAVED="$HOME/Library/Application Support/Shelf-real"
PREFS="$HOME/Library/Application Support/Shelf-real-prefs.plist"

die() { echo "error: $*" >&2; exit 1; }

# Compiles a Swift helper once (and again when its source changes), then runs it.
tool() {
  local name=$1; shift
  mkdir -p "$BIN"
  if [ ! -x "$BIN/$name" ] || [ "$HERE/$name.swift" -nt "$BIN/$name" ]; then
    swiftc -O "$HERE/$name.swift" -o "$BIN/$name" || die "couldn't compile $name.swift"
  fi
  "$BIN/$name" "$@"
}

quit_shelf() { pkill -x Shelf 2>/dev/null || true; sleep 1.5; }

keycode() {
  case "$1" in
    a) echo 0;; s) echo 1;; d) echo 2;; f) echo 3;; h) echo 4;; g) echo 5;; z) echo 6;; x) echo 7;;
    c) echo 8;; v) echo 9;; b) echo 11;; q) echo 12;; w) echo 13;; e) echo 14;; r) echo 15;; y) echo 16;;
    t) echo 17;; 1) echo 18;; 2) echo 19;; 3) echo 20;; 4) echo 21;; 6) echo 22;; 5) echo 23;; 9) echo 25;;
    7) echo 26;; 8) echo 28;; 0) echo 29;; o) echo 31;; u) echo 32;; i) echo 34;; p) echo 35;; l) echo 37;;
    j) echo 38;; k) echo 40;; ,|comma) echo 43;; n) echo 45;; m) echo 46;;
    return|enter) echo 36;; tab) echo 48;; space) echo 49;; delete|backspace) echo 51;; esc|escape) echo 53;;
    left) echo 123;; right) echo 124;; down) echo 125;; up) echo 126;;
    *) die "unknown key: $1";;
  esac
}

press() {
  local combo; combo=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  local key="${combo##*+}" mods="" part
  [ "$combo" = "+" ] && die "unknown key: +"
  if [ "$combo" != "$key" ]; then
    local rest="${combo%+*}"
    local IFS=+
    for part in $rest; do
      case "$part" in
        cmd|command) mods+="${mods:+, }command down";;
        shift) mods+="${mods:+, }shift down";;
        opt|option|alt) mods+="${mods:+, }option down";;
        ctrl|control) mods+="${mods:+, }control down";;
        *) die "unknown modifier: $part";;
      esac
    done
  fi
  local code; code=$(keycode "$key")
  if [ -n "$mods" ]; then
    osascript -e "tell application \"System Events\" to key code $code using {$mods}"
  else
    osascript -e "tell application \"System Events\" to key code $code"
  fi
}

case "${1:-}" in
  sandbox-on)
    [ -e "$SAVED" ] && die "already on: $SAVED exists. Run 'demo.sh sandbox-off' first."
    quit_shelf
    if [ -d "$DATA" ]; then mv "$DATA" "$SAVED"; else mkdir -p "$SAVED"; fi
    # Settings: saved, then cleared, so the Settings screenshot shows defaults (no ignored apps,
    # no per-app styles) and screenshots taken meanwhile don't become cards.
    if defaults export "$BUNDLE" "$PREFS" 2>/dev/null; then defaults delete "$BUNDLE" 2>/dev/null || true; fi
    defaults write "$BUNDLE" addScreenshots -bool false
    open -a Shelf
    sleep 2
    echo "Sandbox on: Shelf is empty, with default settings."
    echo "Your history is in: $SAVED"
    echo "Put it back with: scripts/media/demo.sh sandbox-off"
    ;;
  sandbox-off)
    [ -e "$SAVED" ] || die "nothing to put back: $SAVED doesn't exist."
    quit_shelf
    rm -rf "$DATA"
    mv "$SAVED" "$DATA"
    if [ -f "$PREFS" ]; then
      defaults delete "$BUNDLE" 2>/dev/null || true
      defaults import "$BUNDLE" "$PREFS"
      rm -f "$PREFS"
    else
      defaults delete "$BUNDLE" 2>/dev/null || true
    fi
    open -a Shelf
    echo "Sandbox off: your history and settings are back."
    ;;
  status)
    if [ -e "$SAVED" ]; then echo "sandbox: ON (your history is in $SAVED)"; else echo "sandbox: off"; fi
    if pgrep -x Shelf >/dev/null; then echo "Shelf: running"; else echo "Shelf: not running"; fi
    ;;
  copy-demo) shift; tool demo-content "$@";;
  press) [ $# -eq 2 ] || die "usage: demo.sh press COMBO"; press "$2";;
  type)
    [ $# -eq 2 ] || die "usage: demo.sh type TEXT"
    osascript -e 'on run argv' -e 'tell application "System Events" to keystroke (item 1 of argv)' -e 'end run' "$2"
    ;;
  screen) tool windows --screen;;
  windows) shift; tool windows "$@";;
  shot-window) [ $# -eq 3 ] || die "usage: demo.sh shot-window ID FILE"; screencapture -x -o -l"$2" "$3"; echo "$3";;
  shot-rect) [ $# -eq 3 ] || die "usage: demo.sh shot-rect X,Y,W,H FILE"; screencapture -x -R"$2" "$3"; echo "$3";;
  click) [ $# -eq 3 ] || die "usage: demo.sh click X Y"; tool mouse click "$2" "$3";;
  drag) [ $# -eq 5 ] || die "usage: demo.sh drag X1 Y1 X2 Y2"; tool mouse drag "$2" "$3" "$4" "$5";;
  record)
    [ $# -eq 4 ] || die "usage: demo.sh record X,Y,W,H SECONDS FILE.mov"
    screencapture -x -v -k -V "$3" -R"$2" "$4"
    echo "$4"
    ;;
  gif)
    [ $# -ge 3 ] || die "usage: demo.sh gif IN.mov OUT.gif [WIDTH] [FPS]"
    command -v ffmpeg >/dev/null || die "needs ffmpeg: brew install ffmpeg"
    command -v gifski >/dev/null || die "needs gifski: brew install gifski"
    width=${4:-1200}; fps=${5:-15}
    frames=$(mktemp -d /tmp/shelf-frames.XXXXXX)
    ffmpeg -loglevel error -i "$2" -vf "fps=$fps,scale=$width:-1:flags=lanczos" "$frames/f%04d.png"
    gifski --quiet --fps "$fps" --quality 85 -o "$3" "$frames"/f*.png
    rm -rf "$frames"
    ls -lh "$3"
    ;;
  shrink)
    shift
    for f in "$@"; do
      w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/ {print $2}')
      if [ "${w:-0}" -gt 2000 ]; then sips --resampleWidth 2000 "$f" >/dev/null; fi
      if command -v pngquant >/dev/null; then pngquant --force --skip-if-larger --quality 75-95 --ext .png "$f" || true; fi
      ls -lh "$f"
    done
    ;;
  *)
    sed -n '2,24p' "$0"
    exit 2
    ;;
esac
