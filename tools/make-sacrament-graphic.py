#!/usr/bin/env python3
"""Build the 1920x1080 "stream paused for the sacrament" graphic.

Downloads The Good Shepherd from churchofjesuschrist.org (personal, church-related,
noncommercial use) unless --image is given, crops it to 16:9, darkens the bottom and writes
the message on top. The painting is not stored in this repo.
"""
import argparse
import io
import urllib.request
from PIL import Image, ImageDraw, ImageFont

PAINTING_URL = ("https://www.churchofjesuschrist.org/imgs/75e126dbc032d0810fc934018c5ca415116ce5cb"
                "/full/1920,/0/default?download=true")
TITLE = "The stream is paused for the administration of the Sacrament"
SUBTITLE = "We will resume the broadcast after the Sacrament is completed."
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf"
W, H = 1920, 1080


def fit(img):
    """Fill 1920x1080: crop wide pictures, or float a tall picture over a blurred copy of itself."""
    ratio = img.width / img.height
    if ratio >= 1.4:  # close to widescreen: scale to the width and crop a 16:9 window near the top
        img = img.resize((W, round(W / ratio)), Image.LANCZOS)
        top = min(60, img.height - H) if img.height > H else 0
        img = img.crop((0, top, W, top + min(H, img.height)))
        return img if img.height == H else img.resize((W, H), Image.LANCZOS)
    from PIL import ImageFilter
    bg = img.resize((W, round(W / ratio)), Image.LANCZOS)
    bg = bg.crop((0, (bg.height - H) // 2, W, (bg.height - H) // 2 + H)).filter(ImageFilter.GaussianBlur(40))
    fg = img.resize((round(H * ratio), H), Image.LANCZOS)
    bg.paste(fg, ((W - fg.width) // 2, 0))
    return bg


def wrap(draw, text, font, width):
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=font) <= width:
            line = trial
        else:
            lines.append(line)
            line = word
    return lines + [line]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", help="use this picture instead of downloading the painting")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    if args.image:
        img = Image.open(args.image)
    else:
        req = urllib.request.Request(PAINTING_URL, headers={"User-Agent": "Mozilla/5.0"})
        img = Image.open(io.BytesIO(urllib.request.urlopen(req, timeout=60).read()))
    img = fit(img.convert("RGB"))

    # dark gradient across the bottom third so the text stays readable
    shade = Image.new("L", (1, H))
    for y in range(H):
        t = max(0.0, (y - H * 0.55) / (H * 0.45))
        shade.putpixel((0, y), int(215 * t ** 1.3))
    img = Image.composite(Image.new("RGB", (W, H), (8, 12, 20)), img, shade.resize((W, H)))

    d = ImageDraw.Draw(img)
    title_font = ImageFont.truetype(FONT, 52)
    sub_font = ImageFont.truetype(FONT, 38)
    lines = wrap(d, TITLE, title_font, W - 240)
    y = H - 70 - 46 - 66 * len(lines)
    for line in lines:
        d.text((W / 2, y), line, font=title_font, fill="white", anchor="ma",
               stroke_width=2, stroke_fill=(0, 0, 0))
        y += 66
    d.text((W / 2, H - 100), SUBTITLE, font=sub_font, fill=(235, 235, 235), anchor="ma",
           stroke_width=2, stroke_fill=(0, 0, 0))
    img.save(args.out)
    print(f"Wrote {args.out}")


main()
