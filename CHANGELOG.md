# Changelog

All notable changes to Shelf are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-11-18

Shelf 2.0 is about what happens between copying and pasting: choose how each paste lands, change images
and files on the way, grab text from anywhere on screen, and let secrets clean themselves up.

### Added

**Pasting**
- **Paste As (⌘K, or right-click → Paste As):** every way to paste the selected card, each picked with
  one letter. Text: with formatting, as plain text, or as **Markdown** (bold, italic, links, code and
  lists carried over); UPPERCASE, lowercase, Capitalize Words, Trim Whitespace (removes trailing
  spaces, shared indentation and extra blank lines), Join Lines, and Format JSON (keeps key order).
  Links: Remove Tracking. Images: Paste Text in Image (the text Shelf recognized). Files: Paste File
  Paths or File Names. The card itself isn't changed.
- **Paste Lines One by One (⌘K, then S):** a card with several lines (names, IDs, emails) becomes a
  paste stack: each ⌘V pastes the next line. For filling forms and spreadsheets from a list.
- **Paste style per app:** the bottom right of the shelf says what Return pastes in the app you're
  pasting into (for example "Excel: Plain Text"). Click it to choose formatted or plain text for that
  app, or the default for every other app; Shelf remembers it. The default is in Settings (**Return
  pastes**), replacing Paste as Plain Text by Default.
- **Paste the previous copy (⌥⇧⌘V)** anywhere, without opening the shelf; press it again to swap back.
- **Snippets:** pinned text can hold `{{date}}`, `{{time}}`, `{{datetime}}`, `{{isodate}}`,
  `{{clipboard}}` and `{{uuid}}`, filled in when it's pasted.

**Images and files**
- **The paste box:** Return on an image or file opens a small box just above the card, with the name,
  a format menu (PNG, JPEG, HEIC, TIFF, GIF, PDF), the size (75%, 50%, 25%) and quality, and the
  result's real size next to the original's. Return again pastes: the original if nothing changed (so
  Return, Return is a normal paste), otherwise the new file. ⇧Return pastes the original straight away;
  ⌘C copies, ⌘S saves. Tab moves between the controls and the arrow keys change them. Turn it off with
  **Ask before pasting images and files** in Settings.
- **Markup (⌘E on any image card, or right-click → Markup…):** draw **arrows**, **boxes**,
  **highlights** and **text** on an image, in seven colors, **blur** what shouldn't be seen (a coarse
  mosaic of its own colors, which can't be undone like a light blur) and **crop** it. Works for copied
  images, screenshots and image files. A R H T B C pick the tools, 1–7 the colors, ⌘Z undoes, Return
  is Done. **Fully keyboard-driven too:** Space adds a mark in the middle, Tab selects, the arrows
  move it, ⌥ arrows resize it, ⌫ deletes it. The preview is drawn the same way as the file; the card
  itself stays as it was.
- **Copy as File (⌘R, or right-click):** the same box for any card. Text becomes a Plain Text (any
  extension you type, such as `deploy.sh`), Markdown, RTF, Word or HTML file. Renaming a JPEG or HEIC
  without resizing copies it unchanged.
- **Screenshots go straight into the shelf:** screenshots macOS saves as files (⇧⌘3, ⇧⌘4, ⇧⌘5)
  appear in History as images, ready to paste, mark up or convert, and their text is searchable. Only
  files macOS marks as screenshots count. macOS asks once for access to the folder they're saved in.
- **Grab Text from Screen (⇧⌘2):** drag over anything on screen (a video, an image, a locked PDF, an
  app that won't let you select) and the text in it is copied, ready to paste, and added to History.
  Recognized on this Mac; Shelf asks for Screen Recording permission the first time.
- **File cards show the file itself:** a screenshot or photo, the first page of a PDF, the start of a
  text file. **Space** on a file opens the full Quick Look preview, where PDFs and text scroll and
  videos play.
- **Drag cards out** of the shelf into other apps. Images arrive as a PNG file with a readable name.
  **Several at once:** drag one of the marked cards to drag them all, or a card holding several files
  to drag every file.

**Finding and tidying**
- **Search by app and date:** `from:slack`, `@today`, `@yesterday`, `@week`, `@month`, combined with
  words as you like.
- **Filter by kind:** ↑ ↓, or the icons next to the search field, show only text, links, images or files.
- **Act on several cards:** mark them with ⌘S, ⇧-click or ⇧← ⇧→, then ⌘P pins, ⌘⌫ deletes and ⌘J
  joins them into one card, besides Return (paste stack) and ⌥Return (all at once).
- **Undo delete (⌘Z):** brings back the cards you just deleted, up to the last 20 deletes.
- Text cards that are just a hex color (`#1E90FF`) show the color.

**Privacy**
- **Passwords and keys are spotted and deleted:** text that looks like an API key (OpenAI, Anthropic,
  GitHub, AWS, Stripe, Slack, Google), a private key, a JWT, a `password=…` line, a link with a password
  in it or a card number gets a 🔑 card that shows only its last four characters and is deleted after 5
  minutes unless you pin it. **Forget Last 5 Minutes** in the Shelf menu deletes what you just copied.
- **Links are cleaned as you copy them:** utm_…, fbclid, gclid and similar are removed from the card
  and from the clipboard, so ⌘V pastes the clean link too. Turn it off in Settings.

**Settings and the shelf**
- **Settings window (⌘, in the shelf, or Settings… in the Shelf menu):** record new shortcuts for
  opening the shelf, pasting the previous copy and grabbing text (applied at once; Shelf says if
  another app has them), how long to keep history (1 week to forever), when to delete passwords and
  keys, the paste style and the apps set differently, link cleaning, Ask Before Pasting, Add
  Screenshots, ignored apps, Launch at Login, and whether auto-paste and Screen Recording are allowed.
- A bar at the bottom of the shelf shows what the keys do for the selected card. **Hold ⌘** to see
  ⌘1–⌘9 on the cards and every ⌘ shortcut.
- **Motion:** the shelf slides up as it opens and fades as it closes, the highlight slides between
  tabs and filters, cards ease in and out as you search, filter, pin or delete, the selection glides
  along the row, and the preview and paste box fade in. Pasting still closes the shelf at once. With
  **Reduce motion** on (System Settings → Accessibility → Display), things fade instead of moving.
- The Shelf menu shows the version at the bottom.
- **When auto-paste is off** (macOS hasn't allowed Shelf to press ⌘V), Return no longer seems to do
  nothing: a message says the item was copied, and the shelf shows **Return only copies · Turn on
  auto-paste**. One click clears Shelf's old Accessibility entry (an old one can look switched on
  after an update and still not count) and asks macOS again.

### Changed
- **⌘,** in the shelf opens Settings; the **⋯** button still opens the Shelf menu. Add Screenshots,
  Ask Before Pasting, Paste Style, Ignored Apps and Launch at Login moved from the menu into Settings.
- Changing a shortcut no longer needs Terminal or a restart.
- Clearer empty states (no matches, empty pinboard, empty filter), each saying what to do next.
- The shelf is slightly taller to fit the new bottom bar.

### Fixed
- The first card no longer sits against the shelf's left edge when the shelf opens, and the first and
  last cards keep their margin when you move to them.

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
