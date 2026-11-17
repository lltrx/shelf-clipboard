# Changelog

All notable changes to Shelf are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Paste As (⌘K, or right-click → Paste As):** every way to paste the selected card, each picked with
  one letter. Text: with formatting, as plain text, or as **Markdown** (bold, italic, links, code and
  lists carried over); UPPERCASE, lowercase, Capitalize Words, Trim Whitespace (removes trailing
  spaces, shared indentation and extra blank lines), Join Lines, and Format JSON (keeps key order).
  Links: Remove Tracking (utm_…, fbclid, gclid and others). Images: Paste Text in Image (the text Shelf
  recognized). Files: Paste File Paths or File Names. The card itself isn't changed.
- **Copy as File (⇧⌘C, or right-click):** turn a card into a file with the name and format you choose.
  Images and image files convert to PNG, JPEG, HEIC, TIFF, GIF or PDF, with a quality slider for JPEG
  and HEIC and a size option (75%, 50%, 25%); the form shows the resulting size before you commit.
  Text becomes a Plain Text (any extension you type, such as `deploy.sh`), Markdown, RTF, Word or HTML
  file. Any other file can be renamed. Then press Return to paste the file (into Finder, Mail, Slack…),
  ⌘C to copy it, or ⌘S to save it somewhere.
- **Paste style per app:** the bottom right of the shelf says what Return pastes in the app you're
  pasting into (for example "Excel: Plain Text"). Click it to choose formatted or plain text for that
  app; Shelf remembers it. The list is in the Shelf menu under **Paste Style in Apps**.
- **Filter by kind:** ↑ ↓, or the icons next to the search field, show only text, links, images or files.
- **Drag cards out** of the shelf into other apps. Images arrive as a PNG file with a readable name.
- A bar at the bottom of the shelf shows what the keys do for the selected card. **Hold ⌘** to see
  ⌘1–⌘9 on the cards and every ⌘ shortcut.
- Text cards that are just a hex color (`#1E90FF`) show the color.
- **Motion:** the shelf slides up as it opens and fades as it closes, the highlight slides between
  tabs and filters, cards ease in and out as you search, filter, pin or delete, the selection glides
  along the row, and the preview and Copy as File fade in. Pasting still closes the shelf at once. With
  **Reduce motion** on (System Settings → Accessibility → Display), things fade instead of moving.
- The Shelf menu shows the version at the bottom.

### Changed
- Clearer empty states (no matches, empty pinboard, empty filter), each saying what to do next.
- The shelf is slightly taller to fit the new bottom bar.

## [1.5.0] - 2026-10-23

### Added
- **Paste as Plain Text by Default** in the Shelf menu. When it is on, Return, ⌘1…9 and double-click
  paste without fonts, colors or tables (handy for Excel and web pages), and ⇧ pastes with formatting.

## [1.4.1] - 2026-10-13

### Added
- The Shelf menu is also inside the shelf: the **⋯** button at the top right, or **⌘,**. On crowded
  menu bars (especially on Macs with a notch) macOS can hide Shelf's menu bar icon, which left Pause
  Capture, Ignored Apps and Launch at Login out of reach.

## [1.4.0] - 2026-10-11

### Added
- **Ignored Apps:** never record copies from apps you choose. Right-click a card → **Don't Record
  Copies from <app>**, or menu bar icon → **Ignored Apps** → **Add App…**; click an app there to
  record it again.
- Install with Homebrew: `brew install --cask lltrx/tap/shelf-clipboard`.

## [1.3.1] - 2026-10-11

### Changed
- Passwords copied from password managers are no longer recorded: copies marked concealed
  (`org.nspasteboard.ConcealedType`, used by 1Password, Bitwarden and others) and anything copied
  from Apple's Passwords app or Keychain Access. ⌘V still pastes them as usual.
- While such a password is on the clipboard, History starts with a 🔒 **Password** card that shows
  dots instead of the password and says it isn't saved. Return on it pastes the password. It can't be
  previewed, pinned, edited or stacked, and it disappears once you copy something else.

## [1.3.0] - 2026-10-11

### Changed
- Shelf is now signed with an Apple Developer ID and notarized by Apple, so it opens like any other
  downloaded app — no more **Open Anyway** in System Settings.
- **When updating from 1.2 or 1.2.1, grant Accessibility once more:** in System Settings → Privacy &
  Security → Accessibility, select Shelf, click **−**, then paste once and allow it. Later updates keep
  the permission.

## [1.2.1] - 2026-10-10

### Fixed
- Releases are signed with a stable certificate again. 1.2 was ad-hoc signed, so macOS asked for
  Accessibility permission again after every update. **When updating from 1.2, grant Accessibility one
  last time:** in System Settings → Privacy & Security → Accessibility, remove Shelf with **−**, then
  allow it when Shelf asks. Later updates keep the permission.

### Added
- Unit tests for storage, dedup hashing, link detection, and pinboard backups (`swift test`), run in CI.
- Optional Developer ID signing and notarization in the release script (for maintainers).

## [1.2] - 2026-10-07

First public, open-source release. Shelf is a native macOS clipboard manager (Swift/SwiftUI, no
dependencies) that keeps your clipboard history entirely on your Mac.

### Features
- Clipboard history with text (RTF/HTML/RTFD formatting preserved), links, files, and images.
- Search across text, links, file names, source app, and text recognized inside screenshots
  (on-device OCR via Apple Vision, English and Arabic).
- Pinboards for organizing saved items, with daily automatic JSON backups (last 7 kept).
- Paste stack: queue items and paste them one per ⌘V, or all at once.
- Paste with original formatting or as plain text; in-place editing before pasting.
- Global ⇧⌘V shortcut (configurable), keyboard-first navigation, menu bar app with no Dock icon.
- Local only: no network code, no account, no iCloud. History is stored with `600`/`700` file
  permissions and never leaves the Mac.

[Unreleased]: https://github.com/lltrx/shelf-clipboard/compare/v1.5.0...HEAD
[1.5.0]: https://github.com/lltrx/shelf-clipboard/compare/v1.4.1...v1.5.0
[1.4.1]: https://github.com/lltrx/shelf-clipboard/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/lltrx/shelf-clipboard/compare/v1.3.1...v1.4.0
[1.3.1]: https://github.com/lltrx/shelf-clipboard/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/lltrx/shelf-clipboard/compare/v1.2.1...v1.3.0
[1.2.1]: https://github.com/lltrx/shelf-clipboard/compare/v1.2...v1.2.1
[1.2]: https://github.com/lltrx/shelf-clipboard/releases/tag/v1.2
