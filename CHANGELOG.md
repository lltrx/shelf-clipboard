# Changelog

All notable changes to Shelf are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/lltrx/shelf-clipboard/compare/v1.2...HEAD
[1.2]: https://github.com/lltrx/shelf-clipboard/releases/tag/v1.2
