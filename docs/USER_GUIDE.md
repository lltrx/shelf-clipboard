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

The bar at the bottom of the shelf always shows what the keys do for the selected card. **Hold ⌘** for
a moment to see every ⌘ shortcut there, and the numbers ⌘1–⌘9 on the first nine cards.

## All shortcuts

These work while the shelf is open.

| Shortcut | What it does |
|---|---|
| ⇧⌘V | Open or close the shelf |
| Type anything | Search text, links, file names, the app it came from, and text inside screenshots |
| ← → | Previous / next card |
| ⌘← ⌘→ | First / last card |
| ↑ ↓ | Show only text, links, images or files, then everything again |
| Return or double-click | Paste (with formatting, or as plain text in apps you've set to plain text) |
| ⇧Return | Paste the other way: plain text instead of formatted, or the reverse |
| ⌘K | Paste As: every way to paste this card (see below) |
| ⌘1 … ⌘9 | Paste card 1–9 directly (add ⇧ for the other way) |
| ⌘C | Copy the card to the clipboard without pasting |
| ⇧⌘C | Copy as File: choose a file name and format (see below) |
| Space | Open the full preview (when the search field is empty) |
| ⌘E | Edit the card before pasting |
| ⌘P | Pin or unpin |
| ⌘N | New pinboard |
| Tab / ⇧Tab | Next / previous tab (History, then each pinboard) |
| ⌘S | Add to or remove from the paste stack |
| ⌘⌫ | Delete the card |
| Esc | Close the preview, then the shelf |

Right-click any card for the same actions with the mouse. You can also **drag a card** out of the shelf
into another app: text, links and files arrive as they are, and images arrive as a PNG file named like
"Image 2026-11-16 at 19.40.12.png".

## Formatting

Text copied from Word, Outlook, Notes or a browser keeps its fonts, bold, links and tables.
**Return** pastes it formatted, **⇧Return** pastes plain text. Formatted cards say "Formatted" at the bottom.

**Choose per app.** The bottom right of the shelf says what Return pastes in the app you're pasting
into, for example **Excel: Plain Text** or **Word: Formatted**. Click it and pick **With Formatting** or
**Plain Text**; Shelf remembers it for that app, so you can paste plain text into Excel, Terminal and
Slack and keep formatting in Word and Mail without thinking about it. ⇧Return still pastes the other way.
The apps you've set are listed in the Shelf menu under **Paste Style in Apps**; click one to forget it.

For every other app, **Paste as Plain Text by Default** in the Shelf menu (menu bar icon, or **⋯** /
**⌘,** in the shelf) decides. Cells copied from a spreadsheet paste as text separated by tabs, one row
per line.

## Paste As (⌘K)

**⌘K** (or right-click → **Paste As**) lists every way to paste the selected card. Press the letter
shown next to one, or click it. The card itself stays as it was.

| Card | Options |
|---|---|
| Formatted text | Paste with Formatting (F), Paste as Plain Text (T), Paste as **Markdown** (M): bold, italic, links, code and lists become Markdown |
| Any text | UPPERCASE (U), lowercase (L), Capitalize Words (C), Trim Whitespace (W): removes trailing spaces, the indentation all lines share, and extra blank lines; Join Lines (J): one line, for text copied from a PDF; Format JSON (P): indents JSON, keeping its key order |
| Link | Remove Tracking from Link (R): drops `utm_…`, `fbclid`, `gclid` and similar parameters |
| Image | Paste Text in Image (T): the text Shelf recognized in it |
| Files | Paste File Paths (P), Paste File Names (N) |

Every card also has **Copy as File…** (E).

## Copy as File (⇧⌘C)

Turns a card into a real file with the name and format you choose: rename a screenshot before
sending it, convert a HEIC photo to JPEG, or turn a snippet into `notes.md`.

1. Select a card and press **⇧⌘C** (or right-click → **Copy as File…**, or ⌘K then E).
2. Type a **name**. The extension follows the format, so you don't need to type it.
3. Pick a **format**:
   - Images, and image files such as HEIC or PNG photos: PNG, JPEG, HEIC, TIFF, GIF or PDF. For JPEG
     and HEIC, set the **quality**; for any image, the **size** (75%, 50%, 25%). The form shows the
     result, such as "1440 × 900 · 312 KB", so you can see the size before you send it.
   - Text: Plain Text, Markdown, Rich Text (RTF), Word Document or Web Page (HTML). With Plain Text
     you can type any extension, such as `deploy.sh` or `data.csv`.
   - Other files keep their format and are renamed. With several files, the name you type is numbered
     ("Trip 1.jpg", "Trip 2.jpg"); leave it empty to keep their names.
4. Press **Return** to paste the file into the app you were in (a Finder window, Mail, Slack, Messages…),
   **⌘C** to copy it, or **⌘S** to save it somewhere. **Esc** goes back.

Converting re-encodes the picture: its orientation is kept, other details such as where a photo was
taken are left out. The files are made in Shelf's own folder and deleted after a day; the app you paste
them into keeps its own copy. Shelf remembers the format and quality you used last.

## Finding things

- **Type** to search text, links, file names, the app something was copied from, and text in images.
- **↑ ↓**, or the icons next to the search field, show only **text**, **links**, **images** or **files**.
  It combines with search and with pinboards.
- Text cards that are just a color code like `#1E90FF` show the color.

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

Click the clipboard icon in the menu bar, or the **⋯** button at the top right of the shelf (⌘,),
for the menu below. The ⋯ button is handy when your menu bar is crowded: on Macs with a notch, macOS
hides menu bar icons that don't fit, and Shelf's may be one of them.

- **Pause Capture:** stop recording copies until you turn it back on.
- **Paste as Plain Text by Default:** what Return pastes in apps you haven't set.
- **Paste Style in Apps:** the apps you've set to formatted or plain text; click one to forget it.
- **Launch at Login:** start Shelf automatically.
- **Export Pinboards… / Import Pinboards…:** save your pinboards to a file, or bring them back.
- **Show History Folder:** where everything is stored.
- **Clear Unpinned History…:** delete everything except pinned cards.

## Privacy and storage

- Everything stays in `~/Library/Application Support/Shelf/` on your Mac, readable only by your account.
- **Passwords from password managers are not recorded.** 1Password, Bitwarden, Apple Passwords and
  similar apps mark the passwords they copy as concealed; Shelf skips those. ⌘V still pastes them as
  usual. While one is on the clipboard, the first card in History is a 🔒 **Password** card (the
  password itself is never shown); Return on it pastes the password.
- **Ignore apps you never want recorded.** Right-click a card → **Don't Record Copies from <app>**, or
  menu bar icon → **Ignored Apps** → **Add App…**. Click an app in that list to record it again.
  Cards already in History stay until you delete them (⌘⌫).
- **Everything else you copy is recorded**, including passwords you copy from ordinary text. Use
  **Pause Capture** before copying something sensitive, or delete the card afterwards with ⌘⌫.
- History is kept for **30 days**. Pinned cards are kept forever.
- Pinboards are backed up automatically once a day to the `Backups` folder (last 7 days kept).
- Files made by Copy as File, and images you drag out of the shelf, are kept in the `Exports` folder
  for a day, then deleted.
- Exported pinboard files can contain secrets. Keep them somewhere private, not in shared or cloud folders.

## Troubleshooting

| Problem | Fix |
|---|---|
| Return closes the shelf but nothing is pasted | Shelf needs Accessibility permission: System Settings → Privacy & Security → Accessibility → turn Shelf on. The item is still on the clipboard, so ⌘V works by hand. |
| macOS keeps asking for Accessibility although Shelf is on | The entry belongs to an older copy. Select Shelf in that list, click **−**, then paste once and allow it again. |
| ⇧⌘V does nothing | Another app owns the shortcut (often Paste). Quit it, then quit and reopen Shelf. To use a different shortcut, see "Changing the shortcut" in INSTALL.md. |
| A copy is missing | Capture may be paused (menu bar), or the app marked the copy as temporary, which Shelf respects. |
| Shelf isn't running after a restart | Turn on **Launch at Login** in the Shelf menu (⋯ in the shelf, or the menu bar icon). |
