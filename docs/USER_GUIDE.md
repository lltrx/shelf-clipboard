# Shelf user guide

Shelf keeps everything you copy on your Mac (text, links, images, files) and lets you paste any of it
again from a row of cards at the bottom of the screen. Nothing is sent anywhere: no iCloud, no account,
no subscription.

## Everyday use

1. Copy things as usual (⌘C). Shelf records each copy in the background.
2. Press **⇧⌘V** anywhere. The shelf slides up with your most recent copies first.
3. Move with **← →**, or just start typing to search.
4. Press **Return** to paste the selected card into the app you were in.

Press **Esc** or click anywhere else to close the shelf.

## All shortcuts

These work while the shelf is open.

| Shortcut | What it does |
|---|---|
| ⇧⌘V | Open or close the shelf |
| Type anything | Search text, links, file names, the app it came from, and text inside screenshots |
| ← → | Previous / next card |
| ⌘← ⌘→ | First / last card |
| Return or double-click | Paste with original formatting |
| ⇧Return | Paste as plain text |
| ⌘1 … ⌘9 | Paste card 1–9 directly (add ⇧ for plain text) |
| ⌘C | Copy the card to the clipboard without pasting |
| Space | Open the full preview (when the search field is empty) |
| ⌘E | Edit the card before pasting |
| ⌘P | Pin or unpin |
| ⌘N | New pinboard |
| Tab / ⇧Tab | Next / previous tab (History, then each pinboard) |
| ⌘S | Add to or remove from the paste stack |
| ⌘⌫ | Delete the card |
| Esc | Close the preview, then the shelf |

Right-click any card for the same actions with the mouse.

## Formatting

Text copied from Word, Outlook, Notes or a browser keeps its fonts, bold, links and tables.
**Return** pastes it formatted, **⇧Return** pastes plain text. Formatted cards say "Formatted" at the bottom.

## Pinboards

Pinned cards never expire. Group them into named pinboards, such as "Code commands" or "Email replies".

- **Pin:** select a card and press **⌘P**. With more than one pinboard, a menu asks which one; press 1–9 to pick.
- **Unpin:** press **⌘P** again on a pinned card.
- **New pinboard:** press **⌘N** (or click **+** next to the tabs), type a name, press Return.
- **Switch:** press **Tab** to move between History and each pinboard.
- **Rename or delete:** right-click the pinboard's tab. Deleting a pinboard moves its cards back to History; nothing is lost.

## Preview and edit

- **Space** opens a large preview above the shelf: the full text with formatting, the full image
  (with any text found in it), or the full file paths. ← → keeps working while it is open.
- **⌘E** makes the text editable. Then **⌘Return** pastes your edited version, **⇧⌘Return** pastes it
  as plain text, and **Esc** cancels. The edited version is saved as a new card; the original stays.

## Paste stack

For filling forms or spreadsheets with several items in order:

1. Select a card and press **⌘S**. It is marked "Stack 1" and the selection moves to the next card.
   Keep pressing ⌘S (or move with ← →) to add more, in the order you want them.
2. Press **Return**. The first item is pasted.
3. Each time you press **⌘V** after that, the next item is pasted. The menu bar shows progress, e.g. `2/5`.

**⌥Return** instead pastes all stacked items at once, one per line. Copying something new ends the
stack; you can also end it or skip an item from the menu bar.

## Searching screenshots

Shelf reads the text inside copied images on your Mac (English and Arabic), so typing a word that
appears in a screenshot finds it. Image cards with recognized text say "Contains text".

## Menu bar

Click the clipboard icon in the menu bar for:

- **Pause Capture:** stop recording copies until you turn it back on.
- **Launch at Login:** start Shelf automatically.
- **Export Pinboards… / Import Pinboards…:** save your pinboards to a file, or bring them back.
- **Show History Folder:** where everything is stored.
- **Clear Unpinned History…:** delete everything except pinned cards.

## Privacy and storage

- Everything stays in `~/Library/Application Support/Shelf/` on your Mac, readable only by your account.
- **Everything you copy is recorded, including passwords.** Use **Pause Capture** before copying
  something sensitive, or delete the card afterwards with ⌘⌫.
- History is kept for **30 days**. Pinned cards are kept forever.
- Pinboards are backed up automatically once a day to the `Backups` folder (last 7 days kept).
- Exported pinboard files can contain secrets. Keep them somewhere private, not in shared or cloud folders.

## Troubleshooting

| Problem | Fix |
|---|---|
| Return closes the shelf but nothing is pasted | Shelf needs Accessibility permission: System Settings → Privacy & Security → Accessibility → turn Shelf on. The item is still on the clipboard, so ⌘V works by hand. |
| macOS keeps asking for Accessibility although Shelf is on | The entry belongs to an older copy. Select Shelf in that list, click **−**, then paste once and allow it again. |
| ⇧⌘V does nothing | Another app owns the shortcut (often Paste). Quit it, then quit and reopen Shelf. To use a different shortcut, see "Changing the shortcut" in INSTALL.md. |
| A copy is missing | Capture may be paused (menu bar), or the app marked the copy as temporary, which Shelf respects. |
| Shelf isn't running after a restart | Turn on **Launch at Login** in the menu bar menu. |
