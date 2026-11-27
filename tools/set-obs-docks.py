#!/usr/bin/env python3
"""Install the OBS window layout in obs-configuration/obs-layout.ini, and open OBS in studio mode.

Usage: set-obs-docks.py OBS_CONFIG_DIR   (e.g. ~/.var/app/com.obsproject.Studio/config/obs-studio)
Every run puts the layout back (docks with PTZ Controls in place, side docks, vertical mixer; not the window's position or size, which stays as each computer has it) and turns
studio mode on, so a dock closed or moved, or studio mode turned off, by accident is fixed by the next setup or
update. Also turns off OBS's popup about closing a dock. Close OBS first: it writes its own layout when it exits.
The Windows twin is set-obs-docks.ps1.
"""
import configparser
import pathlib
import sys

LAYOUT = pathlib.Path(__file__).resolve().parent.parent / "obs-configuration" / "obs-layout.ini"


def load(path):
    cp = configparser.ConfigParser(interpolation=None)
    cp.optionxform = str  # OBS keys are case-sensitive
    if path.exists():
        cp.read(path, encoding="utf-8-sig")
    return cp


def save(cp, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        cp.write(f, space_around_delimiters=False)


def section(cp, name):
    if not cp.has_section(name):
        cp.add_section(name)
    return cp[name]


ini = pathlib.Path(sys.argv[1]) / "user.ini"
user = load(ini)
# Skip OBS's "You just closed a dockable window" popup.
section(user, "General")["WarnedAboutClosingDocks"] = "true"
window = section(user, "BasicWindow")
window.update(load(LAYOUT)["BasicWindow"])
window.pop("ChurchLayout", None)  # left by an older version of this script, which installed each layout only once
# Studio mode on. OBS saves the mode on exit, so this is only the starting state; the next run sets it again.
window["PreviewProgramMode"] = "true"
save(user, ini)
print(f"OBS layout (PTZ Controls docked) installed in {ini}; studio mode on")
