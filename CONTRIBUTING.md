# Contributing to Shelf

Thanks for your interest in Shelf! It's a small, native macOS clipboard manager with no third-party
dependencies, so the project is easy to build and hack on.

## Ground rules

- **Shelf is local-only by design.** It has no network code, no account, and no telemetry. Please
  don't add any. Anything that sends clipboard data off the Mac is out of scope.
- Keep it dependency-free (Swift + SwiftUI + AppKit + the system `sqlite3` only).
- Match the existing style: flat Apple-native look, keyboard-first, no shadows or badges.

## Building from source

**Requirements:** macOS 14+ and Apple's Command Line Tools (`xcode-select --install`). Full Xcode is
not required.

```sh
./build.sh            # build the universal app into build/Shelf.app
./build.sh --install  # build, install to ~/Applications/Shelf.app, and launch
swift build           # faster inner loop while iterating (native arch, debug)
swift test            # run the unit tests
```

See [docs/HANDOVER.md](docs/HANDOVER.md) for the architecture, source layout, and how each file fits
together — read it before a non-trivial change.

## Testing a change

Run `swift test`. The unit tests in `Tests/ShelfTests/` cover the non-UI logic: storage
(`Store.swift`), dedup hashing and link detection (`Monitor.swift`), and pinboard backups
(`Backup.swift`). Each test uses its own temporary folder, never your real history in
`~/Library/Application Support/Shelf`. If you change that logic, add or update a test.

The UI isn't covered by tests, so also check it by hand:

1. `./build.sh --install` and confirm the app launches and the menu bar icon appears.
2. Copy a few things (text, a link, a file, an image), press **⇧⌘V**, and check they show up.
3. Exercise whatever your change touches — paste, search, pinboards, the paste stack, OCR, backups.

CI runs `swift test` and the full universal build on every pull request, so make sure both pass
before you open one.

## Pull requests

1. Fork the repo and create a branch off `main`.
2. Keep each PR focused on one change; describe what and why.
3. Make sure `swift test` and `./build.sh` succeed locally.
4. Open the PR against `main`. A maintainer will review it.

## Reporting bugs and requesting features

Open an issue — there are templates for bug reports and feature requests. For bugs, include your macOS
version, whether you're on Apple Silicon or Intel, and clear steps to reproduce.

> **Never paste real clipboard contents, screenshots of private data, or exported pinboard files into
> an issue or PR** — Shelf captures everything you copy, including passwords. Redact first.

## A note on releases

Official release builds are signed with the maintainer's Apple Developer ID and notarized by Apple.
CI has neither the signing key nor the notarization credentials, so release downloads are published
by the maintainer rather than built automatically. Your own builds are signed locally (or ad-hoc),
which is fine for development. See
[docs/HANDOVER.md](docs/HANDOVER.md) for the full release process.
