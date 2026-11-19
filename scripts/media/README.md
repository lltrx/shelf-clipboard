# Capturing Shelf's README screenshots and demo GIF

A runbook for a Claude Code session running **on the Mac** (it needs the screen), in this repository.
It produces the images in `docs/images/`, the README section that shows them, and a commit on the
branch `claude/epic-hopper-bt9cd0`. Your real clipboard history and settings are moved aside first and
put back at the end, so no personal data reaches the images.

## Starting the session (for the person)

1. On the Mac with Shelf 2.0 installed (in `/Applications`, through Homebrew), open Terminal:
   ```sh
   cd ~/Projects/shelf_clipboard && git fetch origin claude/epic-hopper-bt9cd0 && git checkout claude/epic-hopper-bt9cd0 && git pull
   ```
2. Start `claude` there and paste the prompt below.
3. When asked, allow the terminal app (Terminal, iTerm or the Claude app) in **System Settings →
   Privacy & Security → Accessibility** (to press keys and move the mouse) and **Screen & System Audio
   Recording** (to take screenshots of other apps). Quit and reopen the terminal if macOS says so.
4. Switch the keyboard input source to **ABC** or **U.S.** while it runs, and don't touch the keyboard or
   mouse during the scripted parts. It takes about 20 to 30 minutes.

### The prompt

> You're running on my Mac, in my Shelf repository, on the branch `claude/epic-hopper-bt9cd0`. Follow
> `scripts/media/README.md` from "The run" to the end to capture Shelf 2.0's README screenshots and demo
> GIF, update the README, and push the branch. Use `scripts/media/demo.sh` for every key press,
> screenshot and recording. Look at each image you take and redo it until it matches the shot list.
> Before you change anything on my Mac that the runbook doesn't mention, ask me. Whatever happens, end
> with `scripts/media/demo.sh sandbox-off` so my real clipboard history and settings come back, and
> check `demo.sh status` says the sandbox is off. Don't push to main and don't make a release.

## The run

### 1. Check the setup

```sh
scripts/media/demo.sh status            # sandbox must be off, Shelf running
scripts/media/demo.sh screen            # screen size and scale (expect scale 2 on a Retina Mac)
command -v ffmpeg gifski pngquant       # if any is missing, ask, then: brew install ffmpeg gifski pngquant
defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light   # note it, to restore at the end
```

If `demo.sh status` says the sandbox is **on**, a previous run didn't finish: run `sandbox-off` first.
The first `screen` or `windows` call compiles the Swift helpers into `/tmp/shelf-media-bin` (about a
minute).

### 2. Sandbox and appearance

```sh
scripts/media/demo.sh sandbox-on
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false'
```

`sandbox-on` quits Shelf, moves `~/Library/Application Support/Shelf` to `Shelf-real`, saves Shelf's
settings to a plist and clears them (so Settings shows the defaults and screenshots don't become
cards), then opens Shelf empty. From here on, any failure means: fix it or stop, but finish with
`sandbox-off`.

Shots are taken in Light mode. If the person had Dark mode on, turn it back on at the end.

### 3. The scene

Open a blank TextEdit document filling the area above the shelf, so the shelf has something to paste
into and the shots have a quiet background:

```sh
osascript -e 'tell application "TextEdit" to activate' -e 'tell application "TextEdit" to make new document'
scripts/media/demo.sh screen     # use "visible": the area without the menu bar and the Dock
```

Set the TextEdit window's bounds to the visible area's left edge + 8 and right edge − 8, from the top of
the visible area + 8 down to about 330 points above its bottom (the shelf is 312 tall plus 8 of margin),
with `osascript -e 'tell application "TextEdit" to set bounds of front window to {L, T, R, B}'`.
In TextEdit, choose **Format → Make Rich Text** if the document is plain, so pasted formatting shows.

### 4. Fill the shelf

```sh
scripts/media/demo.sh copy-demo
```

This copies nine items, each from a fitting app (TextEdit, Notes, Terminal, Safari):

1. a list of names
2. JSON on one line
3. Arabic text
4. Swift code
5. a color code
6. a GitHub link with tracking (Shelf cleans it)
7. a fake API key (a 🔑 card)
8. an order receipt image
9. formatted meeting notes

The notes end up at the front of the row. The fake key is deleted after 5 minutes: before a shot that
should show it, copy it again with `copy-demo key notes` (so the notes stay first). Wait 5 seconds
after the image so Shelf has read its text. Bring TextEdit back to the front afterwards
(`osascript -e 'tell application "TextEdit" to activate'`).

Then make a pinboard for the pinboard shot:

```sh
scripts/media/demo.sh copy-demo snippet
scripts/media/demo.sh press cmd+shift+v      # open the shelf; the snippet is the first card, selected
scripts/media/demo.sh press cmd+p            # no pinboards yet: Shelf asks for a new one's name
scripts/media/demo.sh type "Replies"
scripts/media/demo.sh press return           # creates "Replies" and pins the snippet into it
scripts/media/demo.sh press esc
```

Check with a quick screenshot that a "Replies" tab exists and holds the snippet. Then run
`copy-demo key notes` so the key card is fresh and the notes are first in History.

### 5. Screenshots

How to take each one:

- Open the state with key presses, waiting about 0.6 s between steps (`sleep 0.6`).
- Find the window with `scripts/media/demo.sh windows`. The shelf is the wide window at the bottom, about
  312 points tall; the paste box sits above it; Settings is titled "Shelf Settings".
- Capture it with `shot-window ID FILE`, which keeps a single window and leaves out the shadow. When the
  shot needs two windows (a box and the card under it), use `shot-rect X,Y,W,H FILE` with a rectangle
  around both, plus 12 points of margin.
- Save into `/tmp/shelf-shots/` first and **look at every image**. Redo it until it matches the
  description below.
- Close what you opened with `esc` before the next shot.

| File | How to get there | What it must show |
|---|---|---|
| `shelf.png` | `press cmd+shift+v` | The whole shelf: tabs, filter icons, search, the row of cards with the formatted notes selected (first), the 🔑 key card visible, the bottom bar with the keys and "Plain Text / Formatted" at the right. |
| `paste-as.png` | shelf open, notes selected, `press cmd+k` | The Paste As menu with its letters, and the card it belongs to. Use `shot-rect` around the menu and the left part of the shelf. |
| `paste-box.png` | shelf open; `press right` until the receipt is selected; `press return`; in the box `press tab` (Format), `press right` until JPEG; `press tab` (Size), `press right` (75%), `press right` (50%) | The paste box above the receipt card: name, JPEG, 50%, quality, and the "861 × 539 · … KB" result line. `shot-rect` around the box and the card. |
| `markup.png` | receipt selected, `press cmd+e` (Markup opens straight away). Then: `press a`, `press space` (arrow in the middle); move it with `press right`/`press down` (shift for big steps) until the tip, moved with `opt+right`/`opt+down`, points at "$42.00". `press t`, `press space`, `type "Due Friday"`, `press return`; move it next to the arrow. `press b`, `press space`; move the blur down over the email row with `press down`. `press esc` to let go of the selection. | The Markup editor with the arrow, the text and the blurred email; nothing selected. `shot-window`. Leave it open for the next step only if needed; `press esc` twice closes it without keeping anything. |
| `search.png` | `press cmd+shift+v`, `type "order"` | The shelf filtered to the receipt (found by the text inside the image), the search field showing "order". |
| `preview.png` | shelf open, receipt selected, `press space` | The large preview above the shelf showing the receipt and "Contains text". `shot-window` on the preview window. |
| `pinboards.png` | shelf open, `press tab` to "Replies" | The Replies pinboard with the snippet card (`{{clipboard}}`, `{{date}}`). |
| `settings.png` | shelf open, `press cmd+,` | The Settings window at the top: Shortcuts (⇧⌘V, ⌥⇧⌘V, ⇧⌘2) and the start of Pasting. `shot-window`. Close it with `press cmd+w`. |

After all eight, shrink them and copy them into the repository:

```sh
scripts/media/demo.sh shrink /tmp/shelf-shots/*.png
cp /tmp/shelf-shots/*.png docs/images/
```

### 6. The demo GIF

Record the bottom part of the screen, from the top of the TextEdit window to the bottom of the shelf
(points, from `screen` and `windows`), while the steps below run. Start the recording in the background,
wait a second, then run the steps with a pause between each:

```sh
scripts/media/demo.sh record X,Y,W,H 32 /tmp/shelf-shots/demo.mov &
```

1. `press cmd+shift+v` (wait 1.2 s). The formatted notes are first: `press return`. They paste into
   TextEdit with formatting (wait 1.5 s).
2. `press return` in TextEdit twice for space. `press cmd+shift+v`, `type "order"` (wait 1 s),
   `press cmd+e` (wait 1.2 s).
3. `press space` (an arrow in the middle); a few `press shift+right` / `press shift+down` and
   `press opt+right` until it points at the total (wait 0.3 s between presses). `press b`,
   `press space`, `press shift+down` once or twice over the email. `press return` (Done), then
   `press return` (paste): the marked-up receipt lands in TextEdit (wait 1.5 s).
4. `press cmd+shift+2`, then `drag` over a line of the pasted notes in TextEdit (screen points;
   find them with a quick screenshot first). Wait for the "Copied N words" message (2 s), then
   `press return` and `press cmd+v` in TextEdit to paste the text.

Rehearse the steps once without recording, and adjust the waits and key counts until it looks right.
Clear TextEdit between takes (`press cmd+a`, `press delete`). Then turn the recording into a GIF and
check it:

```sh
scripts/media/demo.sh gif /tmp/shelf-shots/demo.mov /tmp/shelf-shots/demo.gif 1200 15
```

Look at a few frames (extract them with ffmpeg if needed). Keep it under about 8 MB: if it's bigger,
use width 1000 or 12 fps. Then copy it to `docs/images/demo.gif`.

### 7. The README

Replace the images at the top of `README.md` (the `demo.gif` line, the `shelf.png` line and the
three-column table) with:

```markdown
![Shelf 2.0: pasting formatted notes, marking up a receipt with an arrow and a blur, and grabbing text from the screen](docs/images/demo.gif)

![The shelf at the bottom of the screen: formatted notes, a receipt image, a cleaned link, code, a color, Arabic text, JSON and a masked API key](docs/images/shelf.png)

| Paste As (⌘K) | The paste box (Return on an image) | Markup (⌘E) |
|---|---|---|
| ![The Paste As menu: with formatting, plain text, Markdown, and text changes](docs/images/paste-as.png) | ![Converting the receipt to a JPEG at half size before pasting](docs/images/paste-box.png) | ![An arrow, a label and a blurred email on the receipt](docs/images/markup.png) |

| Search, even inside images | Full preview (Space) | Pinboards and snippets |
|---|---|---|
| ![Searching "order" finds the receipt by the text in it](docs/images/search.png) | ![The receipt in the large preview](docs/images/preview.png) | ![A Replies pinboard with a snippet using {{clipboard}} and {{date}}](docs/images/pinboards.png) |

![Settings: shortcuts, paste style, history, privacy](docs/images/settings.png)
```

Keep the rest of the README as it is. Delete any image in `docs/images/` the README no longer uses.

### 8. Put everything back

Always, even after a failure:

```sh
osascript -e 'tell application "TextEdit" to close every document saving no'
scripts/media/demo.sh sandbox-off
scripts/media/demo.sh status        # must say: sandbox: off
```

If the person had Dark mode on, turn it back on:

```sh
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'
```

Tell them they can switch the input source back.

### 9. Commit and push

Look at every image in `docs/images/` once more for anything personal: names in the menu bar, other
windows, notifications. Then:

```sh
git add docs/images README.md
git commit -m "README: Shelf 2.0 screenshots and demo GIF"
git push origin claude/epic-hopper-bt9cd0
```

Don't push to `main` and don't run `scripts/release.sh`. Report which shots you took, the GIF's size,
and anything that didn't work as described here.

## Notes

- **Keys:** `press` sends physical keys through System Events, the same way Shelf reads them, so it
  works with any keyboard layout. `type` sends characters, which is why the input source has to be
  ABC or U.S.
- **Coordinates:** all coordinates are points with the origin at the top left of the main screen.
  Screenshots come out at the screen's scale (2× on Retina).
- **If it gets stuck:** if the shelf doesn't open, Shelf's shortcut may differ. `sandbox-on` resets it
  to ⇧⌘V; if it still doesn't open, check that Shelf is running and that nothing else owns ⇧⌘V.
- **If Return only copies:** the shelf says "Return only copies". Shelf itself needs Accessibility (it
  already has it on this Mac). The demo only pastes into TextEdit, so ⌘V by hand also works.
- **`demo-content --receipt FILE`** writes the receipt image on its own, if a shot needs it as a file.
