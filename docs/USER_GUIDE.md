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

These work while the shelf is open, except the first three, which work anywhere. Those can be changed
in **Settings** (⌘,).

| Shortcut | What it does |
|---|---|
| ⇧⌘V | Open or close the shelf |
| ⌥⇧⌘V | Paste the copy before the last one, without opening the shelf (press again to swap back) |
| ⇧⌘2 | Grab text from screen: drag over anything, and the text in it is copied (see below) |
| Type anything | Search text, links, file names, the app it came from, and text inside screenshots. `from:slack` and `@today` narrow it down (see Finding things) |
| ← → | Previous / next card |
| ⌘← ⌘→ | First / last card |
| ↑ ↓ | Show only text, links, images or files, then everything again |
| Return or double-click | Paste (with formatting, or as plain text in apps you've set to plain text). On an image or file, a small box opens first (see below) |
| ⇧Return | Paste the other way: plain text instead of formatted, or the reverse. On an image or file: paste it as it is |
| ⌘K | Paste As: every way to paste this card (see below) |
| ⌘1 … ⌘9 | Paste card 1–9 directly (add ⇧ for the other way) |
| ⌘C | Copy the card to the clipboard without pasting |
| ⌘R | Copy as File: the same box, for any card (see below) |
| Space | Open the full preview (when the search field is empty) |
| ⌘E | Images: Markup (arrows, text, blur, crop). Text: edit it before pasting |
| ⌘P | Pin or unpin |
| ⌘N | New pinboard |
| Tab / ⇧Tab | Next / previous tab (History, then each pinboard) |
| ⌘S, ⇧-click | Mark the card (for the paste stack, or to act on several cards) |
| ⇧← ⇧→ | Mark the cards you move over |
| ⌘J | Join the marked cards into one, a line each |
| ⌘⌫ | Delete the card, or the marked cards |
| ⌘Z | Bring back the cards you just deleted |
| ⌘, | Settings |
| Esc | Close the preview, then the shelf |

Right-click any card for the same actions with the mouse. You can also **drag a card** out of the shelf
into another app: text, links and files arrive as they are, and images arrive as a PNG file named like
"Image 2026-11-16 at 19.40.12.png".

## Formatting

Text copied from Word, Outlook, Notes or a browser keeps its fonts, bold, links and tables.
**Return** pastes it formatted, **⇧Return** pastes plain text. Formatted cards say "Formatted" at the bottom.

**Choose the default.** In **Settings** (⌘, in the shelf, or Settings… in the Shelf menu), **Return
pastes** sets what Return, ⌘1…9 and double-click paste: **With formatting** or **Plain text**. ⇧ always pastes the other way. Cells copied from a spreadsheet paste as plain text
separated by tabs, one row per line.

**Choose per app.** The bottom right of the shelf says what Return pastes in the app you're pasting
into, for example **Excel: Plain Text** or **Word: Formatted**. Click it and pick **With Formatting** or
**Plain Text**; Shelf remembers it for that app, so you can paste plain text into Excel, Terminal and
Slack and keep formatting in Word and Mail without thinking about it. ⇧Return still pastes the other way.
The same menu also sets the default for every other app. The apps you've set are listed in Settings
under **Return pastes**; click ⓧ next to one to make it follow the default again.

## Paste As (⌘K)

**⌘K** (or right-click → **Paste As**) lists every way to paste the selected card. Press the letter
shown next to one, or click it. The card itself stays as it was.

| Card | Options |
|---|---|
| Formatted text | Paste with Formatting (F), Paste as Plain Text (T), Paste as **Markdown** (M): bold, italic, links, code and lists become Markdown |
| Any text | UPPERCASE (U), lowercase (L), Capitalize Words (C), Trim Whitespace (W): removes trailing spaces, the indentation all lines share, and extra blank lines; Join Lines (J): one line, for text copied from a PDF; Format JSON (P): indents JSON, keeping its key order |
| Link | Remove Tracking from Link (R): drops `utm_…`, `fbclid`, `gclid` and similar parameters |
| Image | Paste Text in Image (T): the text Shelf recognized in it |
| Text with several lines | Paste Lines One by One (S): each ⌘V pastes the next line (see Paste stack) |
| Files | Paste File Paths (P), Paste File Names (N) |

Every card also has **Copy as File…** (E).

## Rename, resize or convert before pasting

Press **Return** on an image or file card and a small box opens just above it:

- **Name:** type a new name. The extension follows the format, so you don't need to type it.
- **Format** (the menu next to the name): PNG, JPEG, HEIC, TIFF, GIF or PDF for images and image
  files; Plain Text, Markdown, Rich Text (RTF), Word or HTML for text. Other files keep their format and
  are renamed. With several files, the name you type is numbered ("Trip 1.jpg", "Trip 2.jpg"); leave
  it empty to keep their names.
- **Size:** Original, 75%, 50% or 25%, and **Quality** for JPEG and HEIC.
- Under them, the result, such as "invoice.jpg · 861 × 539 · 180 KB", next to what the card is now,
  so you can see the size before you send it.
- **Markup** (⌘E), for a single image: arrows, boxes, highlights, text, blur and crop. See below.

**Keyboard:** **Tab** and **⇧Tab** move between Name, Format, Size and Quality (a blue ring shows
which). On Format, Size or Quality, **← →** (or **↑ ↓**) change it: the next format, a smaller or
bigger size, higher or lower quality. In the Name field the arrows move the text cursor as usual.

Then **Return** pastes it into the app you were in (a Finder window, Mail, Slack, Messages…), **⌘C**
copies it, **⌘S** saves it somewhere, and **Esc** goes back. If you changed nothing, Return pastes the
card exactly as before, so **Return, Return** is a normal paste. **⇧Return** pastes the original
straight away, in the shelf or in the box.

**⌘R** (or right-click → **Copy as File…**, or ⌘K then E) opens the same box for any card, text
included: turn a snippet into `notes.md` or a Word document. With Plain Text you can type any
extension, such as `deploy.sh` or `data.csv`.

Don't want the box on Return? Turn off **Ask before pasting images and files** in Settings; ⌘R still
opens it.

### Markup: arrows, text, blur and crop

To point at something in an image, or hide a name or a key before you send it, select any image card
(a copied image, a screenshot, or an image file) and press **⌘E**, or right-click it → **Markup…**.
In the paste box, press ⌘E, click **Markup**, or Tab to it and press Return. A box opens with the
image. Pick a tool, then drag on the image:

| Tool | Key | What it does |
|---|---|---|
| Arrow | A | Drag from where the arrow starts to what it points at |
| Box | R | Drag around something to draw a box |
| Highlight | H | Drag over text to highlight it, like a marker |
| Text | T | Click where the text goes, type, then **Return** (Esc removes it) |
| Blur | B | Drag over what to hide. It becomes large blocks of its own colors; unlike a light blur, the original can't be recovered from it |
| Crop | C | Drag around what to keep. Dragging again replaces the crop |

Arrows, boxes and text come in seven colors: click one, or press **1–7**. **⌘Z** undoes the last
step, **Return** is Done and **Esc** cancels.

**With the keyboard only:**

| Keys | What they do |
|---|---|
| A R H T B C | Pick a tool |
| Space | Add one in the middle of the image (with Text, start typing there) |
| Tab / ⇧Tab | Select the next / previous mark, blurred area or crop |
| ← → ↑ ↓ | Move what's selected (hold ⇧ for bigger steps) |
| ⌥ ← → ↑ ↓ | Resize it from its bottom right corner (an arrow: move its tip) |
| 1–7 | Color, for new marks and the selected one |
| Return | On selected text: change it. Otherwise: Done |
| ⌫ | Delete what's selected (with nothing selected: clear everything) |
| Esc | Let go of the selection; with nothing selected, cancel |

The mouse and keys mix: draw with the mouse, then nudge with the arrows. Clicking a mark selects it.

Back in the box, the line under the name says what you did ("2 marks, 1 area hidden, cropped"), and
Return pastes the edited image, ⌘C copies it and ⌘S saves it. The card in the shelf stays as it was.
An edited image keeps its format if you chose one, otherwise it becomes a PNG.

## Finding things

- **Type** to search text, links, file names, the app something was copied from, and text in images.
  Text you grabbed from the screen comes from "Text from Screen", so `from:screen` finds it.
- **`from:` an app** keeps only what was copied there: `from:slack`, `from:chrome invoice`. Part of the
  name is enough.
- **A date:** `@today`, `@yesterday`, `@week` (the last 7 days) or `@month` (the last 30). They combine:
  `from:mail @week total`.
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

### Snippets

Pinned text can hold placeholders that are filled in when you paste it:

| Placeholder | Becomes |
|---|---|
| `{{date}}` | Today's date, as your Mac shows dates (Nov 17, 2026) |
| `{{time}}` | The time (14:05) |
| `{{datetime}}` | Both |
| `{{isodate}}` | 2026-11-17 |
| `{{clipboard}}` | What's on the clipboard right now |
| `{{uuid}}` | A new random ID |

For example, pin `Hi {{clipboard}}, thanks for your order of {{date}}.` and copy a name before pasting
it. Only pinned cards are filled in, so copied code that happens to contain `{{…}}` pastes unchanged.

## Preview and edit

- **Space** opens a large preview above the shelf: the full text with formatting, the full image
  (with any text found in it), or a copied file in Quick Look, the same preview Finder shows (PDFs and
  text scroll, videos play). Several files are listed with a picture of each. ← → keeps working while
  it is open. File cards in the shelf show the file itself too, not just its icon.
- **⌘E** makes the text editable. Then **⌘Return** pastes your edited version, **⇧⌘Return** pastes it
  as plain text, and **Esc** cancels. The edited version is saved as a new card; the original stays.

## Several cards at once

Mark cards with **⌘S** (the selection moves on), **⇧-click**, or **⇧← ⇧→** to mark the cards you move
over. They're numbered in the order you marked them, and the bar at the bottom shows what you can do:

- **Return:** the paste stack (below).
- **⌥Return:** paste them all at once, one per line.
- **⌘J:** join them into one new card, a line each.
- **⌘P:** pin them all (with several pinboards, pick one).
- **⌘⌫:** delete them all. **⌘Z** brings them back.
- **Drag** one of them out of the shelf to drag them all into Finder, Mail, Slack…: files and images as
  files, links as links, text as text. A card holding several files drags every file the same way.

**⌘Z** works for any delete, up to the last 20, while the shelf is open or after.

### Paste stack

For filling forms or spreadsheets with several items in order:

1. Mark the cards in the order you want them.
2. Press **Return**. The first item is pasted.
3. Each time you press **⌘V** after that, the next item is pasted. The menu bar shows progress, e.g. `2/5`.

Copying something new ends the stack; you can also end it or skip an item from the menu bar.

**From one card's lines:** for a list in a single card (names, order numbers, emails), press **⌘K**
then **S** (Paste Lines One by One). Each line becomes a step of the stack, blank lines left out: the
first line is pasted, and each ⌘V after that pastes the next.

## Paste the previous copy

**⌥⇧⌘V**, anywhere, pastes what you copied before the last thing, without opening the shelf. Press it
again to swap back: the one it pasted is now the newest. It pastes the way Return would in that app
(formatted or plain text). Change or turn off the shortcut in Settings.

## Grab text from screen

Press **⇧⌘2** anywhere (or choose **Grab Text from Screen** in the Shelf menu), then drag over the
part of the screen with the text, like taking a screenshot. Press Space first to pick a whole window,
or Esc to cancel. Shelf reads the text on your Mac (English and Arabic), puts it on the clipboard and
adds it to History; a message at the bottom of the screen says how many words it copied. Press **⌘V**
to paste it.

It works where you can't select text: a video, an image, a slide being shared, a locked PDF, an app's
error message.

The first time, macOS asks whether Shelf may record the screen: turn Shelf on in **System Settings →
Privacy & Security → Screen & System Audio Recording**, then try again. Settings shows whether it's
allowed. Change or turn off the shortcut in Settings.

## Screenshots

Screenshots you take with **⇧⌘3**, **⇧⌘4** or **⇧⌘5** appear in History by themselves, as images you
can paste, rename or convert (⌘R), even though macOS saves them as files rather than copying them.
The first time, macOS asks whether Shelf may access the folder they're saved in (the Desktop, unless
you changed it in the Screenshot app's Options); allow it.

- They arrive a few seconds after you take them, when macOS saves the file. For no delay, open the
  Screenshot app (⇧⌘5) → **Options** and turn off **Show Floating Thumbnail**.
- Only files macOS marks as screenshots are added, not other images saved in that folder.
- Don't want this? Turn off **Add screenshots** in Settings. Pause Capture also pauses it.
- To point at something in a screenshot, or hide something before sending it, select it and press
  ⌘E (Markup).

## Searching screenshots

Shelf reads the text inside copied images on your Mac (English and Arabic), so typing a word that
appears in a screenshot finds it. Image cards with recognized text say "Contains text".

## Menu bar

Click the clipboard icon in the menu bar, or the **⋯** button at the top right of the shelf, for the
menu below. The ⋯ button is handy when your menu bar is crowded: on Macs with a notch, macOS hides menu
bar icons that don't fit, and Shelf's may be one of them.

- **Pause Capture:** stop recording copies (and screenshots) until you turn it back on.
- **Settings…** (⌘,): see below.
- **Export Pinboards… / Import Pinboards…:** save your pinboards to a file, or bring them back.
- **Show History Folder:** where everything is stored.
- **Forget Last 5 Minutes:** delete what you copied in the last five minutes (pinned cards stay).
- **Clear Unpinned History…:** delete everything except pinned cards.

## Settings

**⌘,** in the shelf, or **Settings…** in the Shelf menu.

- **Shortcuts:** Open Shelf, Paste previous copy and Grab text from screen. Click one and press the new
  keys (with ⌘, ⌥ or ⌃). It works at once; if another app already has those keys, Shelf says so and
  keeps the old ones. ↺ goes back to the default; ⓧ turns the last two off.
- **Screen Recording:** whether Grab text from screen is allowed, with a button to allow it.
- **Return pastes:** with formatting or plain text, and the apps you've set differently.
- **Remove tracking from copied links:** see Privacy (on).
- **Ask before pasting images and files:** Return opens the box to rename, resize, convert, blur or
  crop first (on).
- **Auto-paste:** whether Shelf may press ⌘V for you, with a button to allow it.
- **Keep history for:** 1 week, 2 weeks, 1 month (the default), 3 months, 1 year or forever. Pinned
  cards are always kept. A shorter time deletes older cards right away.
- **Delete passwords and keys after:** 1, 5 (the default) or 15 minutes, 1 hour, or never. See Privacy.
- **Add screenshots:** put new screenshots in the shelf (on).
- **Ignored apps:** apps whose copies are never recorded. **Add App…**, or ⓧ to record one again.
- **Launch at login:** start Shelf automatically.

## Privacy and storage

- Everything stays in `~/Library/Application Support/Shelf/` on your Mac, readable only by your account.
- **Passwords from password managers are not recorded.** 1Password, Bitwarden, Apple Passwords and
  similar apps mark the passwords they copy as concealed; Shelf skips those. ⌘V still pastes them as
  usual. While one is on the clipboard, the first card in History is a 🔒 **Password** card (the
  password itself is never shown); Return on it pastes the password.
- **Keys, tokens and passwords copied from ordinary text are spotted and deleted.** API keys (OpenAI,
  Anthropic, GitHub, AWS, Stripe, Slack, Google), private keys, JWTs, `password=…` lines, links with a
  password in them and card numbers get a 🔑 card that shows only its last four characters ("••••••••9f2c") and says
  when it will be deleted: after **5 minutes**, unless you pin it. Change the time, or turn it off, in
  Settings.
- **Links are cleaned as you copy them.** Tracking added to links (`utm_source=…`, `fbclid`, `gclid`
  and similar) is removed from the card and from the clipboard, so ⌘V pastes the clean link too. The
  rest of the link stays as it was. Turn it off in Settings.
- **Ignore apps you never want recorded.** Right-click a card → **Don't Record Copies from <app>**, or
  **Settings** → **Ignored apps** → **Add App…**. Cards already in History stay until you delete them (⌘⌫).
- **Copied something you shouldn't have?** Shelf menu → **Forget Last 5 Minutes**, or delete the card
  with ⌘⌫. **Pause Capture** before copying something sensitive keeps it out altogether.
- History is kept for **30 days** unless you change it in Settings. Pinned cards are kept forever.
- Pinboards are backed up automatically once a day to the `Backups` folder (last 7 days kept).
- Files made by Copy as File, and images you drag out of the shelf, are kept in the `Exports` folder
  for a day, then deleted.
- Exported pinboard files can contain secrets. Keep them somewhere private, not in shared or cloud folders.

## Troubleshooting

| Problem | Fix |
|---|---|
| Return closes the shelf but nothing is pasted | Shelf needs Accessibility permission: System Settings → Privacy & Security → Accessibility → turn Shelf on. The item is still on the clipboard, so ⌘V works by hand. |
| macOS keeps asking for Accessibility although Shelf is on | The entry belongs to an older copy. Select Shelf in that list, click **−**, then paste once and allow it again. |
| ⇧⌘V does nothing | Another app owns the shortcut (often Paste). Pick a different one in **Settings** → **Shortcuts** (open it from the menu bar icon), or quit the other app. |
| A copy is missing | Capture may be paused (menu bar), the app may be ignored (Settings), or the app marked the copy as temporary, which Shelf respects. A key or password is deleted after a few minutes unless pinned. |
| Shelf isn't running after a restart | Turn on **Launch at login** in Settings. |
| Grab text from screen finds nothing, or only the desktop picture | Shelf needs Screen Recording: System Settings → Privacy & Security → Screen & System Audio Recording → turn Shelf on, then try again. With a new beta, turn it off and on again. |
