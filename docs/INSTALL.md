# Installing Shelf

Shelf is a free, local-only clipboard history app for macOS. Everything you copy stays on your Mac.

**Requirements:** macOS 14 Sonoma or later, on Apple Silicon or Intel.

## Option A: install the app (recommended)

Download the latest `Shelf-<version>.zip` from the
[Releases page](https://github.com/lltrx/shelf-clipboard/releases) (or use a copy someone shared with you).

1. Double-click the zip to unpack **Shelf.app**.
2. Move **Shelf.app** to your **Applications** folder.
3. Open it. macOS asks whether you want to open an app downloaded from the internet; click **Open**.
   Shelf is signed with an Apple Developer ID and checked by Apple (notarized), so nothing else is
   needed. (Versions 1.2 and 1.2.1 weren't notarized and needed **Open Anyway** in System Settings →
   Privacy & Security.)
4. A clipboard icon appears in the menu bar. Shelf has no Dock icon; that is normal.
5. Click the menu bar icon and turn on **Launch at Login**.
6. Copy something, press **⇧⌘V**, and press **Return** on a card. macOS asks for **Accessibility**
   permission, which Shelf needs to paste into other apps for you. Click **Open System Settings**
   and turn **Shelf** on.

Done. See the user guide (USER_GUIDE.md) for all shortcuts.

> **Work-managed Macs:** if your Mac is managed by your company (for example with Jamf), the
> Accessibility switch may be blocked by policy. Ask your IT team to allow Shelf.

## Option B: build it yourself from source

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
4. Continue from step 5 of Option A.

When you build it yourself, the app is signed only for your Mac. After each rebuild, macOS may ask for
Accessibility again; if so, remove Shelf from the Accessibility list with **−** and allow it again.

## Updating

Quit Shelf (menu bar icon → **Quit Shelf**), replace **Shelf.app** with the new version, and open it.
Your history and pinboards are kept, because they are stored separately from the app.

**Updating from 1.2 or 1.2.1 to 1.3 or later:** Shelf's signature changed to an Apple Developer ID, so
macOS asks for Accessibility once more. In **System Settings → Privacy & Security → Accessibility**,
select Shelf, click **−**, then paste once and allow it again. Later updates keep the permission.

## Changing the shortcut

The default is **⇧⌘V**. To use another one, run this in Terminal, then quit and reopen Shelf:

```sh
defaults write com.turkifaisal.shelf hotkey "cmd+option+v"
```

Use any combination of `cmd`, `option`, `shift`, `ctrl` plus a letter, a digit, or `space`.

## Moving to a new Mac

1. On the old Mac: menu bar icon → **Export Pinboards…** and save the file somewhere private.
2. Install Shelf on the new Mac.
3. On the new Mac: menu bar icon → **Import Pinboards…** and choose that file.

Only pinboards move this way. History expires after 30 days anyway.

## Uninstalling

1. Menu bar icon → turn off **Launch at Login**, then **Quit Shelf**.
2. Move **Shelf.app** to the Trash.
3. Remove it from **System Settings → Privacy & Security → Accessibility** (select it, click **−**).
4. To also delete your clipboard history, pinboards and backups, delete this folder:
   `~/Library/Application Support/Shelf`
   (In Finder: **Go → Go to Folder…**, paste the path, then move the folder to the Trash.)

## Privacy

Shelf has no network code and no account. It records everything you copy, **including passwords**,
in a database on your Mac that only your user account can read. Use **Pause Capture** in the menu bar
before copying something you don't want kept.
