#!/usr/bin/env python3
"""Build the sacrament music playlist: one long MP3 that OBS loops on the Sacrament scene.

OBS's media source plays a single file, so the hymns in audio/sacrament-playlist.txt are
downloaded (piano accompaniments from churchofjesuschrist.org) and joined with ffmpeg.

Usage: make-sacrament-playlist.py --list audio/sacrament-playlist.txt --dir ~/Documents/sacrament
Writes DIR/sacrament-playlist.mp3 (and keeps each hymn in DIR/hymns/). Re-running only downloads
what is missing and only rebuilds the playlist when the list or the hymns changed. A hymn that
cannot be downloaded is skipped with a warning.
"""
import argparse
import pathlib
import re
import subprocess
import sys
import tempfile
import urllib.request

PAGE = "https://www.churchofjesuschrist.org/media/music/songs/{}?lang=eng"
UA = {"User-Agent": "Mozilla/5.0"}
# The page lists every recording; the piano accompaniment is the AUDIO_ACCOMPANIMENT one.
MP3_RE = re.compile(r'"assetType":"AUDIO_ACCOMPANIMENT","distributionUrl":"([^"]+\.mp3)"')


def fetch(url, timeout=60):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
        return r.read()


def read_list(path):
    slugs = []
    for line in path.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line and line not in slugs:
            slugs.append(line)
    return slugs


def download(slug, dest):
    html = fetch(PAGE.format(slug)).decode("utf-8", "replace")
    m = MP3_RE.search(html)
    if not m:
        raise RuntimeError("no piano accompaniment listed on the page")
    data = fetch(m.group(1), timeout=120)
    tmp = dest.with_suffix(".part")
    tmp.write_bytes(data)
    tmp.replace(dest)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", required=True, type=pathlib.Path)
    ap.add_argument("--dir", required=True, type=pathlib.Path)
    args = ap.parse_args()

    out = args.dir / "sacrament-playlist.mp3"
    hymn_dir = args.dir / "hymns"
    hymn_dir.mkdir(parents=True, exist_ok=True)

    files = []
    for slug in read_list(args.list):
        dest = hymn_dir / (slug + ".mp3")
        if not dest.exists() or dest.stat().st_size == 0:
            try:
                download(slug, dest)
                print("downloaded", slug)
            except Exception as e:  # one bad hymn must not lose the others
                print("WARNING: skipping %s: %s" % (slug, e), file=sys.stderr)
                continue
        files.append(dest)

    if not files:
        print("ERROR: no hymns available, playlist not built", file=sys.stderr)
        return 1

    newest = max([args.list.stat().st_mtime] + [f.stat().st_mtime for f in files])
    if out.exists() and out.stat().st_mtime >= newest and out.stat().st_size > 0:
        print("playlist is up to date (%d hymns)" % len(files))
        return 0

    with tempfile.TemporaryDirectory() as td:
        listing = pathlib.Path(td) / "concat.txt"
        listing.write_text("".join("file '%s'\n" % str(f).replace("'", "'\\''") for f in files))
        part = out.with_suffix(".part.mp3")
        # Re-encode to one format so hymns recorded differently still join cleanly.
        cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", str(listing),
               "-vn", "-ac", "2", "-ar", "44100", "-c:a", "libmp3lame", "-q:a", "4", str(part)]
        subprocess.run(cmd, check=True)
        part.replace(out)
    print("built %s from %d hymns" % (out, len(files)))
    return 0


sys.exit(main())
