# Security Policy

Shelf is a clipboard manager, so by design it stores **everything you copy — including passwords,
tokens, and other secrets** — on your Mac. Security is therefore central to the project. This document
describes the threat model and how to report a vulnerability.

## Security model

- **Local only.** Shelf has no network code, no account, and no telemetry. Clipboard data never leaves
  your Mac. It is not synced to iCloud or any server.
- **On-disk storage.** History lives in
  `~/Library/Application Support/Shelf/history.sqlite` and `images/`, created with file mode `600`
  and directory mode `700` — readable only by your macOS user account. Daily pinboard backups under
  `Backups/` and any file you create with **Export Pinboards…** use the same `600` mode.
- **No encryption at rest.** The database is not separately encrypted; it relies on macOS file
  permissions and your account's protection (FileVault, if enabled). Anyone with read access to your
  user account, or an unlocked unencrypted disk, can read your history.
- **Secrets are captured by default.** Copying a password puts it in the history like anything else.
  Use **Pause Capture** before copying sensitive data, or **Clear Unpinned History…** afterward.
- **Exports may contain secrets.** Exported pinboard files embed formatting and images and may contain
  passwords. Keep them somewhere private — not in shared folders, iCloud Drive, or a public repo.
- **Accessibility permission.** Shelf requests macOS Accessibility only to synthesize the paste
  keystroke (⌘V) into the frontmost app. It does not read other apps' contents.

## What is in scope

- Clipboard data being transmitted off the device by any code path.
- History, backups, or exports being written with weaker permissions than described above.
- Any app behavior that exposes stored secrets to another user, app, or process that shouldn't have
  access.
- Memory-safety or injection issues reachable from copied content (e.g. malformed RTF/HTML/images).

## What is out of scope

- An attacker who already has full access to your unlocked macOS user account (they can read the files
  directly regardless of Shelf).
- The absence of at-rest encryption, which is a documented design choice above (feature requests
  welcome as issues, not security reports).
- The "Open Anyway" prompt on versions 1.2 and 1.2.1, which weren't notarized. Releases from 1.3 are
  signed with an Apple Developer ID and notarized.

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue for anything that could
expose users' data.

1. Preferred: open a private advisory via GitHub's
   [**Security → Report a vulnerability**](https://github.com/lltrx/shelf-clipboard/security/advisories/new)
   on this repository.
2. Include the affected version, your macOS version, and steps to reproduce.

You can expect an acknowledgement within a few days. Once a fix is available, it will be released and
the advisory published with credit to the reporter (unless you prefer to remain anonymous).

## Supported versions

Shelf is a single-maintainer project; only the **latest released version** receives fixes. Please make
sure you're on the newest release before reporting.
