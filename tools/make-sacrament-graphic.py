#!/usr/bin/env python3
"""Build the 1920x1080 background for the sacrament scene.

Downloads The Good Shepherd from churchofjesuschrist.org (personal, church-related,
noncommercial use) unless --image is given, crops it to 16:9 and darkens the bottom so the
scene's text layers stay readable. The text itself is OBS text sources in the scene collection,
not part of this picture. The painting is not stored in this repo.
"""
import argparse
import io
import urllib.request
from PIL import Image

PAINTING_URL = ("https://www.churchofjesuschrist.org/imgs/75e126dbc032d0810fc934018c5ca415116ce5cb"
                "/full/1920,/0/default?download=true")
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

    img.save(args.out)
    print(f"Wrote {args.out}")


main()
