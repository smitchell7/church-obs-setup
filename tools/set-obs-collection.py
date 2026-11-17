#!/usr/bin/env python3
"""Make an installed scene collection the one OBS opens with. The Windows twin is set-obs-collection.ps1.

Usage: set-obs-collection.py OBS_CONFIG_DIR COLLECTION.json
       (e.g. ~/.var/app/com.obsproject.Studio/config/obs-studio obs-configuration/sacrament-alkire-and-quail/sacrament-alkire-and-quail.json)
"""
import configparser
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
collection = pathlib.Path(sys.argv[2])
name = json.loads(collection.read_text(encoding="utf-8"))["name"]

ini = root / "user.ini"
user = configparser.ConfigParser(interpolation=None)
user.optionxform = str  # OBS keys are case-sensitive
if ini.exists():
    user.read(ini, encoding="utf-8-sig")
if not user.has_section("Basic"):
    user.add_section("Basic")
user["Basic"]["SceneCollection"] = name
user["Basic"]["SceneCollectionFile"] = collection.name
ini.parent.mkdir(parents=True, exist_ok=True)
with ini.open("w", encoding="utf-8") as f:
    user.write(f, space_around_delimiters=False)
print(f"OBS will open with the '{name}' scene collection.")
