#!/usr/bin/env python3
"""Update the OBS scene collections and the OBS configuration on this computer from this repo.

Installs every collection in obs-configuration/ and the OBS settings the same way setup-obs-flatpak.sh does,
without running the rest of the setup (no software installs, no sudo, no PipeWire audio files, and the video
settings are left alone). The Windows twin is tools/obs-config-update.ps1.

Usage (as the person who uses OBS, not with sudo; close OBS first):
    python3 tools/obs-config-update.py [--default FOLDER]   (FOLDER: a collection folder in obs-configuration/, e.g. sacrament-independence)

- Each file it replaces is saved next to it as *.bak.
- Keeps what was already picked in OBS, by source name: the "USB Audio" microphone, capture devices and
  NDI senders. A new "USB Audio" gets the input the setup script would pick (Sound Blaster, else USB, ...).
- Builds the notch filter plugins (tools/hum-notch-vst/build.sh) into ~/.vst if any are missing, and sets
  VST_PATH for the OBS Flatpak so it finds them.
- Puts back the OBS window layout (obs-configuration/obs-layout.ini)
  every time, and turns studio mode on (tools/set-obs-docks.py).
- Pins OBS to the GNOME dock if it isn't (tools/set-obs-dock-pin.py).
- Only where OBS runs under X11 (a Flatpak override): starts OBS maximized through tools/obs-launch.sh
  (tools/set-obs-launcher.py). On other computers this changes nothing.
- Points OBS's audio monitoring at the speaker that feeds Zoom (tools/set-obs-monitor.py) and turns on the
  WebSocket server, keeping its password (tools/set-obs-websocket.py).
- Asks which collection OBS opens on (the same menu as the setup script), with the current one marked; Enter keeps
  it. --default answers up front. Run without a terminal to ask in, it leaves OBS's current one.
- --list only lists the collections (for the OBS Configuration Reset button, tools/obs-config-reset-button/button.sh).
"""
import argparse
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time

REPO = pathlib.Path(__file__).resolve().parent.parent
OBS_DIR = pathlib.Path.home() / ".var/app/com.obsproject.Studio/config/obs-studio"
SCENES = OBS_DIR / "basic" / "scenes"

parser = argparse.ArgumentParser(description="Update just the OBS scene collections from this repo.")
parser.add_argument("--default", help="the collection OBS opens on (a folder name in obs-configuration/)")
parser.add_argument("--list", action="store_true",
                    help="only list the collections, in menu order, as FOLDER<tab>NAME<tab>current-or-empty, then stop")
args = parser.parse_args()

if not args.list and subprocess.run(["pgrep", "-f", "com.obsproject.Studio"], capture_output=True).returncode == 0:
    sys.exit("Close OBS first, then run this again.")
# Which collection OBS opens on: the same menu, in the same order, as setup-obs-flatpak.sh.
found = sorted(p.name for p in (REPO / "obs-configuration").iterdir() if p.is_dir())
names = [n for n in ("sacrament-alkire-and-quail", "sacrament-independence", "stake-meeting-alkire-and-quail", "stake-meeting-independence", "stake-meeting-independence-control") if n in found]
names += [n for n in found if n not in names]
configs = [REPO / "obs-configuration" / n for n in names]
# Which collection OBS opens on: asked every time, with the one OBS was using marked; Enter keeps it.
current_file = ""
if (OBS_DIR / "user.ini").exists():
    for line in (OBS_DIR / "user.ini").read_text(encoding="utf-8-sig", errors="replace").splitlines():
        if line.startswith("SceneCollectionFile="):
            current_file = line.split("=", 1)[1].strip()
            break
current = current_file.removesuffix(".json") if current_file.removesuffix(".json") in names else ""
if args.list:
    # For the OBS Configuration Reset button (tools/obs-config-reset-button/button.sh), which asks in a window instead.
    for config, n in zip(configs, names):
        collection = next(config.glob("*.json"), None)
        title = json.loads(collection.read_text(encoding="utf-8")).get("name", n) if collection else n
        print(f"{n}\t{title}\t{'current' if n == current else ''}")
    sys.exit(0)
if args.default:
    if args.default not in names:
        sys.exit(f"No collection named {args.default} (have: {', '.join(names)})")
elif sys.stdin.isatty() and names:
    print("Which scene collection should OBS open on?")
    for i, n in enumerate(names, 1):
        print(f"  {i}) {n}" + ("   (current)" if n == current else ""))
    prompt = f"Number (Enter keeps {current}): " if current else "Number: "
    while True:
        answer = input(prompt).strip()
        if not answer and current:
            print(f"Keeping {current}.")
            break
        if answer.isdigit() and 1 <= int(answer) <= len(names):
            args.default = names[int(answer) - 1]
            break
elif current:
    print(f"Keeping the scene collection OBS was using ({current_file}). Use --default NAME to change it.")


def pick_microphone():
    """The input setup-obs-flatpak.sh would pick: the Sound Blaster, else a USB input, else any real input."""
    try:
        out = subprocess.run(["pactl", "list", "short", "sources"], capture_output=True, text=True).stdout
    except FileNotFoundError:
        return "default"
    sources = [line.split("\t")[1] for line in out.splitlines()
               if "\t" in line and not line.split("\t")[1].endswith(".monitor")]
    for test in (lambda s: "sound_blaster" in s.lower(),
                 lambda s: s.lower().startswith("alsa_input.usb"),
                 lambda s: s.startswith("alsa_input.")):
        found = [s for s in sources if test(s)]
        if found:
            return found[0]
    return "default"


microphone = None
SCENES.mkdir(parents=True, exist_ok=True)
print(f"Scene collections from {REPO / 'obs-configuration'}")
for config in configs:
    for src in sorted(config.glob("*.json")):
        dest = SCENES / src.name
        collection = json.loads(src.read_text(encoding="utf-8").replace("@HOME@", str(pathlib.Path.home())))
        old = {}
        if dest.exists():
            try:
                old = {s["name"]: s for s in json.loads(dest.read_text(encoding="utf-8"))["sources"]}
            except (ValueError, KeyError):
                pass
        kept = []
        for s in collection["sources"]:
            settings = s.setdefault("settings", {})
            before = old.get(s["name"], {}).get("settings", {})
            if s.get("id") == "pulse_input_capture" and settings.get("device_id") == "@AUDIO_DEVICE@":
                if before.get("device_id") and before["device_id"] != "@AUDIO_DEVICE@":
                    settings["device_id"] = before["device_id"]
                    kept.append(s["name"])
                else:
                    microphone = microphone or pick_microphone()
                    settings["device_id"] = microphone
            elif s.get("id") == "v4l2_input" and not settings.get("device_id") and before.get("device_id"):
                settings["device_id"] = before["device_id"]
                kept.append(s["name"])
            elif s.get("id") == "ndi_source" and not settings.get("ndi_source_name") and before.get("ndi_source_name"):
                settings["ndi_source_name"] = before["ndi_source_name"]
                kept.append(s["name"])
        if dest.exists():
            shutil.copy2(dest, dest.with_name(f"{dest.name}.{time.strftime('%Y%m%d-%H%M%S')}.bak"))
        dest.write_text(json.dumps(collection, indent=4, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"Updated {src.name} ({collection['name']})")
        if kept:
            print(f"    kept from OBS: {', '.join(kept)}")

# The notch filters on "USB Audio" load VST plugins from ~/.vst. Build any that are missing and point the OBS
# Flatpak at that folder (VST_PATH), as the setup script does; without either, OBS skips those filters.
VST_DIR = pathlib.Path.home() / ".vst"
plugins = {pathlib.PurePosixPath(path).name for c in configs for f in c.glob("*.json")
           for path in re.findall(r'"plugin_path":\s*"([^"]+)"', f.read_text(encoding="utf-8"))}
missing = sorted(name for name in plugins if not (VST_DIR / name).exists())
if missing:
    if shutil.which("gcc"):
        print(f"Building the notch filter plugins into {VST_DIR} (missing: {', '.join(missing)})")
        subprocess.run(["bash", str(REPO / "tools" / "hum-notch-vst" / "build.sh")], check=False)
    else:
        print(f"WARNING: {', '.join(missing)} not in {VST_DIR} and gcc is missing, so the notch filters on "
              "'USB Audio' will not load. Run: sudo apt-get install -y gcc && bash tools/hum-notch-vst/build.sh")
if plugins and shutil.which("flatpak"):
    override = subprocess.run(["flatpak", "override", "--user", "--show", "com.obsproject.Studio"],
                              capture_output=True, text=True).stdout
    if f"VST_PATH={VST_DIR}" not in override:
        result = subprocess.run(["flatpak", "override", "--user", f"--env=VST_PATH={VST_DIR}", "com.obsproject.Studio"])
        if result.returncode == 0:
            print(f"Set VST_PATH={VST_DIR} for OBS, so it loads the notch filter plugins")
        else:
            print("WARNING: could not set VST_PATH for OBS; the notch filters on 'USB Audio' will not load.")

# The window layout and studio mode on, put back every time, as the setup script does.
subprocess.run([sys.executable, "-I", str(REPO / "tools" / "set-obs-docks.py"), str(OBS_DIR)], check=True)
# The rest of the OBS configuration the setup script makes (it never needs sudo):
# audio monitoring into the "OBS Monitoring (not for Zoom)" speaker that feeds Zoom's "OBS Mic", and
# the WebSocket server for remote control (the computer's current password is kept).
subprocess.run([sys.executable, "-I", str(REPO / "tools" / "set-obs-monitor.py"), str(OBS_DIR)], check=True)
env = {k: v for k, v in os.environ.items() if k != "OBS_WEBSOCKET_PASSWORD"}
subprocess.run([sys.executable, "-I", str(REPO / "tools" / "set-obs-websocket.py"), str(OBS_DIR)], check=True, env=env)
# OBS pinned to the GNOME dock (put back if someone unpinned it).
subprocess.run([sys.executable, "-I", str(REPO / "tools" / "set-obs-dock-pin.py")], check=False)
# Only where OBS runs under X11: start it maximized through tools/obs-launch.sh (changes nothing elsewhere).
subprocess.run([sys.executable, "-I", str(REPO / "tools" / "set-obs-launcher.py")], check=False)

if args.default:
    collection = next((REPO / "obs-configuration" / args.default).glob("*.json"))
    subprocess.run([sys.executable, "-I", str(REPO / "tools" / "set-obs-collection.py"), str(OBS_DIR), str(collection)],
                   check=True)
