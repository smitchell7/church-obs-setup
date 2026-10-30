#!/usr/bin/env python3
"""Fill user-data.template.yaml from secrets.env and write user-data (git-ignored)."""
import pathlib
import sys

here = pathlib.Path(__file__).resolve().parent
values = {}
for line in (here / "secrets.env").read_text().splitlines():
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        key, _, val = line.partition("=")
        values[key.strip()] = val.strip()

text = (here / "user-data.template.yaml").read_text()
missing = []
for key, val in values.items():
    token = f"@{key}@"
    if token in text:
        if not val:
            missing.append(key)
        text = text.replace(token, val)
leftover = sorted({w for w in text.split() if w.startswith("@") and w.endswith("@")})
if missing or leftover:
    sys.exit(f"Fill in these values in secrets.env: {', '.join(missing + leftover)}")
(here / "user-data").write_text(text)
print(f"Wrote {here / 'user-data'}. Serve it with the installer; do not commit it.")
