#!/usr/bin/env python3
"""Edits Shelf's demo video from separate takes: cuts, smooth zooms, captions, crossfades, title cards.

    python3 scripts/media/render.py EDIT.json OUT.mp4              the whole video
    python3 scripts/media/render.py EDIT.json OUT.mp4 --only 2,4,5 some segments (e.g. a shorter GIF cut)
    python3 scripts/media/render.py EDIT.json --frame 12.5 F.png    one frame of the timeline, to check a zoom
    python3 scripts/media/render.py EDIT.json --sheet SHEET.png     3 frames of every segment on one sheet

Needs ffmpeg and ffprobe on the PATH, and Pillow (python3 -m pip install pillow). The edit list
format is described in scripts/media/README.md ("Demo video"); edit.example.json is a full example.

A zoom is a list of keyframes: {"t": seconds into the segment, and one of "rect": [x, y, w, h] in
the take's own pixels (a Retina recording is twice the screen points), "area": [x, y, w, h] as
fractions of the take (0 to 1), or "rect": "full"}. Between keyframes the view eases smoothly; before
the first and after the last it holds still. Each rectangle is widened to the output's shape around
its center; what falls outside the take shows the background.
"""
import argparse
import itertools
import json
import math
import os
import shutil
import subprocess
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("render.py needs Pillow: python3 -m pip install pillow")

FONT_CANDIDATES = {
    "regular": ["/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc",
                "/usr/share/fonts/opentype/inter/Inter-Regular.otf",
                "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"],
    "bold": ["/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc",
             "/usr/share/fonts/opentype/inter/Inter-Bold.otf",
             "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"],
    "mono": ["/System/Library/Fonts/SFNSMono.ttf", "/System/Library/Fonts/Menlo.ttc",
             "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"],
}


def die(message):
    sys.exit("render.py: " + message)


def hex_color(value, alpha=None):
    value = value.lstrip("#")
    rgb = tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))
    return rgb if alpha is None else rgb + (alpha,)


def load_font(spec, role, size):
    paths = ([spec["theme"]["fonts"][role]] if spec["theme"].get("fonts", {}).get(role) else []) + FONT_CANDIDATES[role]
    for path in paths:
        if os.path.exists(path):
            try:
                font = ImageFont.truetype(path, size)
                if role == "bold" and path.endswith("SFNS.ttf"):
                    try:
                        font.set_variation_by_name("Bold")
                    except Exception:
                        pass
                elif role == "regular" and path.endswith("SFNS.ttf"):
                    try:
                        font.set_variation_by_name("Medium")
                    except Exception:
                        pass
                return font
            except OSError:
                continue
    return ImageFont.load_default()


def ease(x):
    """Ease in and out (cubic): starts and ends slowly, like a camera move."""
    x = max(0.0, min(1.0, x))
    return 4 * x * x * x if x < 0.5 else 1 - (-2 * x + 2) ** 3 / 2


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "stream=width,height:format=duration", "-of", "json", path],
                         capture_output=True, text=True)
    if out.returncode != 0:
        die(f"can't read {path}: {out.stderr.strip()}")
    info = json.loads(out.stdout)
    stream = info["streams"][0]
    return stream["width"], stream["height"], float(info["format"].get("duration", 0))


class Editor:
    def __init__(self, spec, base_dir):
        self.spec = spec
        self.base_dir = base_dir
        out = spec.get("output", {})
        self.W, self.H = int(out.get("width", 1920)), int(out.get("height", 1080))
        self.fps = int(out.get("fps", 30))
        self.fade = float(spec.get("transition", 0.35))
        theme = spec.setdefault("theme", {})
        self.bg = hex_color(theme.get("background", "#101318"))
        self.fg = hex_color(theme.get("text", "#ffffff"))
        self.muted = hex_color(theme.get("muted", "#a7afbd"))
        self.accent = hex_color(theme.get("accent", "#2f6feb"))
        self.segments = spec.get("segments", [])
        if not self.segments:
            die("the edit list has no segments")
        self.sources = {}
        for i, seg in enumerate(self.segments, 1):
            kind = seg.get("type", "clip")
            if kind in ("clip", "still"):
                path = self.path(seg.get("file", ""))
                if not os.path.exists(path):
                    die(f"segment {i}: no such file: {path}")
                if path not in self.sources:
                    self.sources[path] = probe(path)
                seg["_path"] = path
            elif kind != "title":
                die(f"segment {i}: unknown type {kind!r} (clip, still or title)")
            seg["_duration"] = self.duration(seg, i)

    def path(self, p):
        p = os.path.expanduser(p)
        return p if os.path.isabs(p) else os.path.join(self.base_dir, p)

    def duration(self, seg, i):
        kind = seg.get("type", "clip")
        if kind == "clip":
            w, h, length = self.sources[seg["_path"]]
            start = float(seg.get("in", 0))
            end = float(seg.get("out", length))
            if end <= start:
                die(f"segment {i}: 'out' must be after 'in'")
            return (end - start) / float(seg.get("speed", 1))
        if "duration" not in seg:
            die(f"segment {i}: a {kind} needs a 'duration'")
        return float(seg["duration"])

    # The view: which part of the take fills the frame.

    def base_rect(self, seg):
        w, h, _ = self.sources[seg["_path"]]
        crop = seg.get("crop", self.spec.get("crop"))
        return [float(v) for v in crop] if crop else [0.0, 0.0, float(w), float(h)]

    def fit(self, rect):
        """Widens a rect to the output's shape, around its center."""
        x, y, w, h = rect
        cx, cy = x + w / 2, y + h / 2
        aspect = self.W / self.H
        if w / h < aspect:
            w = h * aspect
        else:
            h = w / aspect
        return [cx - w / 2, cy - h / 2, w, h]

    def view(self, seg, t):
        base = self.base_rect(seg)
        keys = seg.get("zoom") or [{"t": 0, "rect": "full"}]

        def resolve(k):
            if "area" in k:
                fx, fy, fw, fh = (float(v) for v in k["area"])
                return [base[0] + fx * base[2], base[1] + fy * base[3], fw * base[2], fh * base[3]]
            if k.get("rect", "full") == "full":
                return base
            return [float(v) for v in k["rect"]]

        rects = [(float(k["t"]), self.fit(resolve(k))) for k in keys]
        rects.sort(key=lambda k: k[0])
        if t <= rects[0][0]:
            return rects[0][1]
        if t >= rects[-1][0]:
            return rects[-1][1]
        for (t0, r0), (t1, r1) in zip(rects, rects[1:]):
            if t0 <= t <= t1:
                e = ease((t - t0) / (t1 - t0) if t1 > t0 else 1)
                c0 = (r0[0] + r0[2] / 2, r0[1] + r0[3] / 2)
                c1 = (r1[0] + r1[2] / 2, r1[1] + r1[3] / 2)
                w = r0[2] * (r1[2] / r0[2]) ** e     # zoom evenly: width changes geometrically
                cx = c0[0] + (c1[0] - c0[0]) * e
                cy = c0[1] + (c1[1] - c0[1]) * e
                h = w * self.H / self.W
                return [cx - w / 2, cy - h / 2, w, h]
        return rects[-1][1]

    def frame_from(self, source, rect):
        """The part of the take inside rect, scaled to the output; outside the take shows the background."""
        x, y, w, h = rect
        out = Image.new("RGB", (self.W, self.H), self.bg)
        sx0, sy0 = max(0.0, x), max(0.0, y)
        sx1, sy1 = min(float(source.width), x + w), min(float(source.height), y + h)
        if sx1 <= sx0 or sy1 <= sy0:
            return out
        scale = self.W / w
        piece = source.resize((max(1, round((sx1 - sx0) * scale)), max(1, round((sy1 - sy0) * scale))),
                              Image.LANCZOS, box=(sx0, sy0, sx1, sy1))
        out.paste(piece, (round((sx0 - x) * scale), round((sy0 - y) * scale)))
        return out

    # Overlays.

    def caption_layer(self, text):
        size = round(self.H * 0.036)
        font = load_font(self.spec, "regular", size)
        layer = Image.new("RGBA", (self.W, self.H), (0, 0, 0, 0))
        draw = ImageDraw.Draw(layer)
        left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
        pad_x, pad_y = round(size * 0.9), round(size * 0.55)
        box_w, box_h = right - left + 2 * pad_x, bottom - top + 2 * pad_y
        bx = (self.W - box_w) // 2
        by = self.H - round(self.H * 0.07) - box_h
        draw.rounded_rectangle([bx, by, bx + box_w, by + box_h], radius=box_h // 2, fill=(16, 19, 24, 205))
        draw.text((bx + pad_x - left, by + pad_y - top), text, font=font, fill=self.fg + (255,))
        return layer

    def title_card(self, seg):
        card = Image.new("RGB", (self.W, self.H), self.bg)
        draw = ImageDraw.Draw(card)
        items = []
        icon = None
        if seg.get("icon"):
            try:
                icon = Image.open(self.path(seg["icon"])).convert("RGBA")
                side = round(self.H * 0.15)
                icon = icon.resize((side, side), Image.LANCZOS)
                items.append(("icon", side))
            except OSError:
                icon = None
        title_font = load_font(self.spec, "bold", round(self.H * 0.085))
        sub_font = load_font(self.spec, "regular", round(self.H * 0.034))
        code_font = load_font(self.spec, "mono", round(self.H * 0.026))
        if seg.get("title"):
            items.append(("title", draw.textbbox((0, 0), seg["title"], font=title_font)))
        if seg.get("subtitle"):
            items.append(("subtitle", draw.textbbox((0, 0), seg["subtitle"], font=sub_font)))
        if seg.get("code"):
            items.append(("code", draw.textbbox((0, 0), seg["code"], font=code_font)))
        gap = round(self.H * 0.03)

        def height(item):
            kind, value = item
            if kind == "icon":
                return value
            pad = round(self.H * 0.022) if kind == "code" else 0
            return value[3] - value[1] + 2 * pad

        total = sum(height(i) for i in items) + gap * (len(items) - 1)
        y = (self.H - total) // 2
        for kind, value in items:
            if kind == "icon":
                card.paste(icon, ((self.W - value) // 2, y), icon)
            else:
                left, top, right, bottom = value
                text = seg[kind]
                font = {"title": title_font, "subtitle": sub_font, "code": code_font}[kind]
                x = (self.W - (right - left)) // 2
                if kind == "code":
                    pad = round(self.H * 0.022)
                    draw.rounded_rectangle([x - 2 * pad, y, x + right - left + 2 * pad, y + bottom - top + 2 * pad],
                                           radius=round(pad * 0.9), fill=tuple(min(255, c + 22) for c in self.bg))
                    draw.text((x - left, y + pad - top), text, font=font, fill=self.fg)
                else:
                    draw.text((x - left, y - top), text, font=font, fill=self.fg if kind == "title" else self.muted)
            y += height((kind, value)) + gap
        return card

    # Frames of one segment.

    def decode(self, seg):
        """Yields the take's frames for this segment at the output frame rate (speed applied)."""
        w, h, _ = self.sources[seg["_path"]]
        size = w * h * 3
        if seg.get("type") == "still":
            cmd = ["ffmpeg", "-v", "error", "-ss", str(seg.get("at", 0)), "-i", seg["_path"],
                   "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
            data = subprocess.run(cmd, capture_output=True).stdout
            if len(data) < size:
                die(f"no frame at {seg.get('at', 0)} s in {seg['_path']}")
            image = Image.frombytes("RGB", (w, h), data[:size])
            while True:
                yield image
        start, speed = float(seg.get("in", 0)), float(seg.get("speed", 1))
        cmd = ["ffmpeg", "-v", "error", "-ss", str(start), "-i", seg["_path"],
               "-t", str(seg["_duration"] * speed),
               "-vf", f"setpts=(PTS-STARTPTS)/{speed},fps={self.fps}",
               "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        last = None
        try:
            while True:
                data = proc.stdout.read(size)
                if len(data) < size:
                    break
                last = Image.frombytes("RGB", (w, h), data)
                yield last
        finally:            # also when the segment needs no more frames
            if proc.poll() is None:
                proc.kill()
            proc.stdout.close()
            proc.wait()
        if last is None:
            die(f"no frames between {start} s and {start + seg['_duration'] * speed} s in {seg['_path']}")
        while True:               # the take ran short: hold its last frame
            yield last

    def segment_frames(self, seg):
        count = max(1, round(seg["_duration"] * self.fps))
        kind = seg.get("type", "clip")
        caption = seg.get("caption")
        layer = self.caption_layer(caption) if caption else None
        cap_in = float(seg.get("caption_in", 0.25))
        cap_out = float(seg.get("caption_out", seg["_duration"] - 0.2))
        if kind == "title":
            card = self.title_card(seg)
            for n in range(count):
                t = n / self.fps
                zoom = 1 + 0.025 * ease(t / max(seg["_duration"], 0.01))      # a slow push in
                w, h = self.W / zoom, self.H / zoom
                yield card.resize((self.W, self.H), Image.LANCZOS,
                                  box=((self.W - w) / 2, (self.H - h) / 2, (self.W + w) / 2, (self.H + h) / 2))
            return
        frames = self.decode(seg)
        for n in range(count):
            t = n / self.fps
            frame = self.frame_from(next(frames), self.view(seg, t))
            if layer is not None:
                alpha = min(1.0, max(0.0, (t - cap_in) / 0.25), max(0.0, (cap_out - t) / 0.25))
                if alpha > 0:
                    faded = layer
                    if alpha < 1:      # fade only the transparency, not the colors
                        faded = layer.copy()
                        faded.putalpha(layer.getchannel("A").point(lambda v: round(v * alpha)))
                    frame = Image.alpha_composite(frame.convert("RGBA"), faded).convert("RGB")
            yield frame

    def timeline(self, only=None):
        """Every output frame, in order, with a crossfade where one segment meets the next."""
        chosen = [s for i, s in enumerate(self.segments, 1) if not only or i in only]
        overlap = round(self.fade * self.fps)
        tail = []          # the last frames of the previous segment, blended into the start of this one
        for index, seg in enumerate(chosen):
            count = max(1, round(seg["_duration"] * self.fps))
            keep = min(overlap, count // 2) if index < len(chosen) - 1 else 0
            new_tail = []
            for n, frame in enumerate(itertools.islice(self.segment_frames(seg), count)):
                if n < len(tail):
                    frame = Image.blend(tail[n], frame, (n + 1) / (len(tail) + 1))
                if n >= count - keep:
                    new_tail.append(frame)
                else:
                    yield frame
            tail = new_tail

    def frame_at(self, t):
        position = 0.0
        for i, seg in enumerate(self.segments, 1):
            if t < position + seg["_duration"] or i == len(self.segments):
                local = max(0.0, min(t - position, seg["_duration"] - 1 / self.fps))
                return self.single(seg, local), i, local
            position += seg["_duration"] - self.fade
        die("time is past the end")

    def single(self, seg, t):
        """One frame of a segment, decoded on its own (for --frame and --sheet)."""
        if seg.get("type", "clip") == "title":
            return self.title_card(seg)
        w, h, _ = self.sources[seg["_path"]]
        at = seg.get("at", 0) if seg.get("type") == "still" else float(seg.get("in", 0)) + t * float(seg.get("speed", 1))
        data = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(at), "-i", seg["_path"], "-frames:v", "1",
                               "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True).stdout
        if len(data) < w * h * 3:
            die(f"no frame at {at:.2f} s in {seg['_path']}")
        frame = self.frame_from(Image.frombytes("RGB", (w, h), data[:w * h * 3]), self.view(seg, t))
        if seg.get("caption"):
            frame = Image.alpha_composite(frame.convert("RGBA"), self.caption_layer(seg["caption"])).convert("RGB")
        return frame


def render(editor, out_path, only):
    total = sum(s["_duration"] for i, s in enumerate(editor.segments, 1) if not only or i in only)
    n_segments = len(only) if only else len(editor.segments)
    total -= editor.fade * max(0, n_segments - 1)
    print(f"rendering {total:.1f} s at {editor.W}×{editor.H}, {editor.fps} fps → {out_path}")
    encoder = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", f"{editor.W}x{editor.H}", "-r", str(editor.fps), "-i", "-",
         "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p",
         "-movflags", "+faststart", out_path],
        stdin=subprocess.PIPE)
    frames = 0
    for frame in editor.timeline(only):
        encoder.stdin.write(frame.tobytes())
        frames += 1
        if frames % (editor.fps * 5) == 0:
            print(f"  {frames / editor.fps:.0f} s", flush=True)
    encoder.stdin.close()
    if encoder.wait() != 0:
        die("ffmpeg couldn't encode the video")
    print(f"done: {frames} frames, {os.path.getsize(out_path) / 1e6:.1f} MB")


def sheet(editor, out_path):
    thumb_w = 480
    thumb_h = round(thumb_w * editor.H / editor.W)
    rows = []
    for i, seg in enumerate(editor.segments, 1):
        d = seg["_duration"]
        row = []
        for f in (0.12, 0.5, 0.88):
            t = d * f
            image = editor.single(seg, t).resize((thumb_w, thumb_h), Image.LANCZOS)
            ImageDraw.Draw(image).text((8, 6), f"{i} @ {t:.1f}s", fill=(255, 64, 64))
            row.append(image)
        rows.append(row)
    out = Image.new("RGB", (thumb_w * 3 + 16, (thumb_h + 8) * len(rows) + 8), (40, 40, 40))
    for r, row in enumerate(rows):
        for c, image in enumerate(row):
            out.paste(image, (4 + c * (thumb_w + 4), 4 + r * (thumb_h + 8)))
    out.save(out_path)
    print(out_path)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("edit", help="the edit list (JSON)")
    parser.add_argument("out", nargs="?", help="the video to write (.mp4)")
    parser.add_argument("--only", help="segment numbers to include, e.g. 2,4,5")
    parser.add_argument("--frame", type=float, help="write the frame at this many seconds into the timeline")
    parser.add_argument("--sheet", action="store_true", help="write a contact sheet of every segment")
    args = parser.parse_intermixed_args()   # options before or after the file names
    for tool in ("ffmpeg", "ffprobe"):
        if not shutil.which(tool):
            die(f"needs {tool}: brew install ffmpeg")
    with open(args.edit) as f:
        spec = json.load(f)
    editor = Editor(spec, os.path.dirname(os.path.abspath(args.edit)))
    if args.sheet:
        sheet(editor, args.out or "sheet.png")
    elif args.frame is not None:
        image, index, local = editor.frame_at(args.frame)
        image.save(args.out or "frame.png")
        print(f"{args.out or 'frame.png'}: segment {index}, {local:.2f} s into it")
    else:
        if not args.out:
            die("say where to write the video, e.g. out.mp4")
        only = [int(x) for x in args.only.split(",")] if args.only else None
        render(editor, args.out, only)


if __name__ == "__main__":
    main()
