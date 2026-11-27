#!/usr/bin/env python3
"""On computers where OBS runs under X11, start OBS through tools/obs-launch.sh, which maximizes it.

Usage: set-obs-launcher.py   (as the person who uses OBS; no sudo)
The OBS Flatpak is "converted to X11" when its overrides (user or system) contain sockets=x11;!wayland or
QT_QPA_PLATFORM=xcb. There, OBS doesn't always come back maximized after a computer restart, so this writes the
user's own copy of OBS's app-menu entry (~/.local/share/applications/com.obsproject.Studio.desktop, the same name,
so the dock icon, the app menu and search use it) with its Exec pointing at obs-launch.sh. If OBS starts
automatically at login (~/.config/autostart/com.obsproject.Studio.desktop), that entry is pointed there too.
On every other computer it does nothing, and removes the copy if an earlier run made one, so OBS starts directly.
setup-obs-flatpak.sh and obs-config-update.py run it.
"""
import pathlib
import re
import subprocess

APP = "com.obsproject.Studio"
MARK = "X-Church-OBS-Launch=true"
REPO = pathlib.Path(__file__).resolve().parent.parent
LAUNCHER = REPO / "tools" / "obs-launch.sh"
SYSTEM_ENTRY = pathlib.Path(f"/var/lib/flatpak/exports/share/applications/{APP}.desktop")
USER_ENTRY = pathlib.Path.home() / ".local/share/applications" / f"{APP}.desktop"
AUTOSTART = pathlib.Path.home() / ".config/autostart" / f"{APP}.desktop"


def overrides():
    out = ""
    for scope in (["--user"], []):
        try:
            out += subprocess.run(["flatpak", "override", *scope, "--show", APP], capture_output=True, text=True,
                                  timeout=20).stdout
        except (OSError, subprocess.SubprocessError):
            pass
    return out


def x11(text):
    sockets = " ".join(re.findall(r"^sockets=(.*)$", text, re.M))
    return "!wayland" in sockets or re.search(r"^QT_QPA_PLATFORM=xcb\s*$", text, re.M) is not None


ORIGINAL = "X-Church-OBS-Original-Exec="


def with_launcher(entry_text):
    """The entry with each Exec that starts OBS going through the launcher. The original Exec lines are kept in
    X-Church-OBS-Original-Exec= lines, so without_launcher() can put them back exactly."""
    if MARK in entry_text:
        entry_text = without_launcher(entry_text)
    out = []
    for line in entry_text.splitlines():
        if line.startswith("Exec=") and APP in line:
            args = line.split(APP, 1)[1].strip()   # whatever came after the app id, e.g. %U
            out.append(ORIGINAL + line[len("Exec="):])
            line = f'Exec=bash "{LAUNCHER}"' + (f" {args}" if args else "")
        out.append(line)
        if line.strip() == "[Desktop Entry]":
            out.append(MARK)
    return "\n".join(out) + "\n"


def without_launcher(entry_text):
    """with_launcher() undone: the original Exec lines back, the marker lines gone."""
    out, original = [], None
    for line in entry_text.splitlines():
        if line == MARK:
            continue
        if line.startswith(ORIGINAL):
            original = line[len(ORIGINAL):]
            continue
        if original is not None and line.startswith("Exec="):
            line, original = "Exec=" + original, None
        out.append(line)
    return "\n".join(out) + "\n"


def ours(path):
    return path.exists() and MARK in path.read_text(errors="replace")


if x11(overrides()):
    if not SYSTEM_ENTRY.exists():
        print(f"OBS runs under X11, but {SYSTEM_ENTRY} is missing; OBS was not pointed at obs-launch.sh.")
    else:
        USER_ENTRY.parent.mkdir(parents=True, exist_ok=True)
        USER_ENTRY.write_text(with_launcher(SYSTEM_ENTRY.read_text()))
        if AUTOSTART.exists():
            AUTOSTART.write_text(with_launcher(AUTOSTART.read_text()))
        print("OBS runs under X11 here: the OBS app-menu entry and dock icon now start it maximized (tools/obs-launch.sh).")
else:
    # Not X11: touch nothing, except to undo what an earlier run made (if the computer went back to Wayland).
    undone = False
    if ours(USER_ENTRY):
        USER_ENTRY.unlink()   # the user copy was ours: removing it brings back OBS's own entry
        undone = True
    if ours(AUTOSTART):
        AUTOSTART.write_text(without_launcher(AUTOSTART.read_text()))
        undone = True
    if undone:
        print("OBS doesn't run under X11 here: removed the maximize launcher, so OBS starts directly.")
