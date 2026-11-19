# Installing Shelf

Shelf is a free, local-only clipboard history app for macOS. Everything you copy stays on your Mac.

**Requirements:** macOS 14 Sonoma or later, on Apple Silicon or Intel.

## Option A: with Homebrew (easiest)

If you use [Homebrew](https://brew.sh), run these in Terminal. Current Homebrew asks you to trust a
tap once before installing from it:

```sh
brew trust lltrx/tap
brew install --cask lltrx/tap/shelf-clipboard
```

This puts Shelf.app in Applications. Continue with **First run** below. Update later with
`brew upgrade --cask shelf-clipboard`.

## Option B: download the app

Download the latest `Shelf-<version>.zip` from the
[Releases page](https://github.com/lltrx/shelf-clipboard/releases) (or use a copy someone shared with you).

1. Double-click the zip to unpack **Shelf.app**.
2. Move **Shelf.app** to your **Applications** folder.
3. Open it. macOS asks whether you want to open an app downloaded from the internet; click **Open**.
   Shelf is signed with an Apple Developer ID and checked by Apple (notarized), so nothing else is
   needed. Continue with **First run** below.

## Option C: build it yourself from source

For people comfortable with Terminal.

1. Install Apple's command line tools (skip if you already have them):
   ```sh
   xcode-select --install
   ```
2. Get the source code — clone `https://github.com/lltrx/shelf-clipboard` (or download the ZIP from
   its GitHub page) — and open Terminal in that folder.
3. Build and install:
   ```sh
   ./build.sh --install
   ```
   This builds Shelf, installs it to `~/Applications/Shelf.app` and opens it.
4. Continue with **First run** below.

When you build it yourself, the app is signed only for your Mac. After each rebuild, macOS may ask for
Accessibility again; if so, remove Shelf from the Accessibility list with **−** and allow it again.

## First run

1. A clipboard icon appears in the menu bar. Shelf has no Dock icon; that is normal.
2. Copy something, press **⇧⌘V**, and press **Return** on a card. macOS asks for **Accessibility**
   permission, which Shelf needs to paste into other apps for you. Click **Open System Settings** and
   turn **Shelf** on. Until then, Return only copies (the shelf says so, with a link to fix it).
3. Open **Settings** (menu bar icon → **Settings…**, or **⌘,** in the shelf) and turn on
   **Launch at login**.

macOS may ask for two more permissions later, only when you use the feature:

- **Files and folders** for the folder screenshots are saved in (usually the Desktop), so screenshots
  you take appear in the shelf. Allow it, or turn off **Add screenshots** in Settings.
- **Screen Recording**, the first time you press **⇧⌘2** (Grab Text from Screen).

Done. See the [user guide](USER_GUIDE.md) for all shortcuts.

> **Work-managed Macs:** if your Mac is managed by your company (for example with Jamf), the
> Accessibility switch may be blocked by policy. Ask your IT team to allow Shelf.

## Updating

**Homebrew:** `brew upgrade --cask shelf-clipboard`.

**Downloaded app:** quit Shelf (menu bar icon → **Quit Shelf**), replace **Shelf.app** with the new
version, and open it.

Your history and pinboards are kept, because they are stored separately from the app, and so is the
Accessibility permission.

**If Return stops pasting after an update** (it only copies): the shelf shows **Return only copies ·
Turn on auto-paste**. Click it, or Settings → Auto-paste → **Turn On…**, and switch Shelf on again. This
happens when the app's signature changes, for example moving from 1.2, from a beta, or from a copy you
built yourself.

## Changing the shortcut

The default is **⇧⌘V**. To use another one, open **Settings** (menu bar icon → **Settings…**, or ⌘,
in the shelf), click the shortcut next to **Open Shelf** and press the new keys. It works at once.
Paste previous copy (**⌥⇧⌘V**) and Grab text from screen (**⇧⌘2**) are changed or turned off the
same way.

Shortcuts use ⌘, ⌥ or ⌃ (and ⇧ if you like) with a letter, a digit or Space.

## Moving to a new Mac

1. On the old Mac: menu bar icon → **Export Pinboards…** and save the file somewhere private.
2. Install Shelf on the new Mac.
3. On the new Mac: menu bar icon → **Import Pinboards…** and choose that file.

Only pinboards move this way, not History.

## Uninstalling

1. Menu bar icon → **Settings…** → turn off **Launch at login**, then menu bar icon → **Quit Shelf**.
2. Installed with Homebrew: `brew uninstall --cask shelf-clipboard`. Otherwise move **Shelf.app** to
   the Trash.
3. Remove it from **System Settings → Privacy & Security → Accessibility** (select it, click **−**).
4. To also delete your clipboard history, pinboards and backups, delete this folder:
   `~/Library/Application Support/Shelf`
   (In Finder: **Go → Go to Folder…**, paste the path, then move the folder to the Trash.)

## Privacy

Shelf has no network code and no account. It records what you copy in a database on your Mac that only
your user account can read.

- Passwords copied from password managers are skipped.
- Keys, tokens and passwords copied from ordinary text (API keys, `password=…`, card numbers…) are
  shown masked and deleted after 5 minutes unless you pin them. Everything else is kept for 30 days
  (both are adjustable in Settings).
- Apps you add to **Ignored apps** in Settings are never recorded.
- **Pause Capture** in the menu bar stops recording until you turn it back on; **Forget Last 5
  Minutes** deletes what you just copied.
