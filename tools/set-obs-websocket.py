#!/usr/bin/env python3
"""Turn on OBS's WebSocket server (port 4455, password required) so it can be controlled remotely.

Usage: set-obs-websocket.py OBS_CONFIG_DIR   (e.g. ~/.var/app/com.obsproject.Studio/config/obs-studio)
The password is taken from $OBS_WEBSOCKET_PASSWORD; if that is empty the existing password is kept, and if
there is none a random one is made and printed. Run again at any time.
"""
import json
import os
import pathlib
import secrets
import sys

path = pathlib.Path(sys.argv[1]) / "plugin_config" / "obs-websocket" / "config.json"
cfg = json.loads(path.read_text()) if path.exists() else {}

password = os.environ.get("OBS_WEBSOCKET_PASSWORD", "") or cfg.get("server_password", "")
generated = not password
if generated:
    password = secrets.token_urlsafe(12)

cfg.update(
    {
        "first_load": False,  # otherwise OBS makes its own password on first start
        "server_enabled": True,
        "server_port": 4455,
        "auth_required": True,
        "server_password": password,
    }
)
cfg.setdefault("alerts_enabled", False)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(cfg, indent=4) + "\n")
path.chmod(0o600)
print(f"OBS WebSocket server enabled on port 4455 ({path})")
if generated:
    print(f"No password was given, so one was made: {password}")
