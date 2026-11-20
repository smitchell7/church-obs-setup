#!/usr/bin/env python3
"""Pin OBS, and the OBS Configuration Reset button, to the GNOME dock (Ubuntu).

Usage: set-obs-dock-pin.py   (as the person who uses OBS, in their desktop session; no sudo)
Adds whichever is missing to the user's dock favourites. The other favourites and their order are kept; OBS goes
before the Terminal if that is pinned, else at the end, and the button right after OBS. The button is pinned only
when it is installed (setup-obs-flatpak.sh adds it). Needs the user's session (D-Bus); without one it does
nothing and says so. setup-obs-flatpak.sh and obs-config-update.py run it, so they are pinned again if someone
unpinned them.
"""
import ast
import pathlib
import shutil
import subprocess
import sys

OBS = "com.obsproject.Studio.desktop"
BUTTON = "church-obs-config-update.desktop"
KEY = ["org.gnome.shell", "favorite-apps"]

if not shutil.which("gsettings"):
    sys.exit(0)  # not GNOME
try:
    out = subprocess.run(["gsettings", "get", *KEY], capture_output=True, text=True, timeout=20, check=True).stdout.strip()
except (subprocess.SubprocessError, OSError):
    print("Could not read the GNOME dock favourites (no desktop session?); OBS was not pinned.")
    sys.exit(0)

favs = ast.literal_eval(out.removeprefix("@as ")) if out else []
before = list(favs)
if OBS not in favs:
    favs.insert(favs.index("org.gnome.Terminal.desktop") if "org.gnome.Terminal.desktop" in favs else len(favs), OBS)
if BUTTON not in favs and pathlib.Path("/usr/share/applications", BUTTON).exists():
    favs.insert(favs.index(OBS) + 1, BUTTON)
if favs == before:
    print("OBS is pinned to the dock.")
    sys.exit(0)
subprocess.run(["gsettings", "set", *KEY, str(favs)], check=True, timeout=20)
print("Pinned to the dock: " + ", ".join(a.removesuffix(".desktop") for a in favs if a not in before))
