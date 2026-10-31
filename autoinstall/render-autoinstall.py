#!/usr/bin/env python3
"""Fill user-data.template.yaml from secrets.env and write user-data (git-ignored)."""
import pathlib
import re
import subprocess
import sys

here = pathlib.Path(__file__).resolve().parent
values = {}
for line in (here / "secrets.env").read_text().splitlines():
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        key, _, val = line.partition("=")
        values[key.strip()] = val.strip()

for user in ("BROADCAST", "LIAHONA", "LEHI"):
    password = values.get(f"PASSWORD_{user}", "")
    if not password:
        sys.exit(f"Set PASSWORD_{user} in secrets.env")
    values[f"HASH_{user}"] = subprocess.run(
        ["openssl", "passwd", "-6", "-stdin"], input=password, capture_output=True, text=True, check=True
    ).stdout.strip()

text = (here / "user-data.template.yaml").read_text()
missing = []
for key, val in values.items():
    token = f"@{key}@"
    if token in text:
        if not val:
            missing.append(key)
        text = text.replace(token, val)
leftover = sorted(set(re.findall(r"@[A-Z][A-Z0-9_]*@", text)))
if missing or leftover:
    sys.exit(f"Fill in these values in secrets.env: {', '.join(missing + leftover)}")
# The installer only reads a file named exactly "user-data"; the named copy is for people.
named = f"{values['HOSTNAME_PREFIX']}-ubuntu-autoinstall.yaml"
for name in ("user-data", named):
    (here / name).write_text(text)
print(f"Wrote {here / 'user-data'} (for the installer, with an empty meta-data next to it) and {here / named}.")
print("Both contain secrets; do not commit them.")
