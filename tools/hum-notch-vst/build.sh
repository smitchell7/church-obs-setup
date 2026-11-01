#!/usr/bin/env bash
# Builds the Hum Notch VST 2.x plugin and installs it to ~/.vst/, where OBS (flatpak included) finds it.
# Run as the normal user (no sudo). Needs gcc (sudo apt-get install -y gcc). Restart OBS afterwards, then
# on the microphone source: Filters > + > VST 2.x Plug-in > HumNotch. The eye icon turns it on and off.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$HOME/.vst"
gcc -O2 -fPIC -shared -fvisibility=hidden -Wall -Wextra -o "$HOME/.vst/HumNotch.so" "$HERE/hum_notch_vst.c" -lm
echo "Installed $HOME/.vst/HumNotch.so"
