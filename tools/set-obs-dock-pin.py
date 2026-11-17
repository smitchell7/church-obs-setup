#!/usr/bin/env python3
"""Pin OBS to the GNOME dock (Ubuntu): add it to the user's dock favourites if it isn't there.

Usage: set-obs-dock-pin.py   (as the person who uses OBS, in their desktop session; no sudo)
The other favourites and their order are kept; OBS goes before the Terminal if that is pinned, else at the end.
Needs the user's session (D-Bus); without one it does nothing and says so. setup-obs-flatpak.sh and
obs-config-update.py run it, so OBS is pinned again if someone unpinned it.
"""
import ast
import shutil
import subprocess
import sys

OBS = "com.obsproject.Studio.desktop"
KEY = ["org.gnome.shell", "favorite-apps"]

if not shutil.which("gsettings"):
    sys.exit(0)  # not GNOME
try:
    out = subprocess.run(["gsettings", "get", *KEY], capture_output=True, text=True, timeout=20, check=True).stdout.strip()
except (subprocess.SubprocessError, OSError):
    print("Could not read the GNOME dock favourites (no desktop session?); OBS was not pinned.")
    sys.exit(0)

favs = ast.literal_eval(out.removeprefix("@as ")) if out else []
if OBS in favs:
    print("OBS is pinned to the dock.")
    sys.exit(0)
i = favs.index("org.gnome.Terminal.desktop") if "org.gnome.Terminal.desktop" in favs else len(favs)
favs.insert(i, OBS)
subprocess.run(["gsettings", "set", *KEY, str(favs)], check=True, timeout=20)
print("Pinned OBS to the dock.")
