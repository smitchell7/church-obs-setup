#!/usr/bin/env bash
# Builds the Hum, Squeal and tone-notch VST 2.x plugins and installs them to ~/.vst/. Every scene collection
# already has them as filters on "USB Audio"; the OBS Flatpak needs VST_PATH=~/.vst for that (the setup script
# sets it). Run as the normal user (no sudo). Needs gcc (sudo apt-get install -y gcc). Restart OBS afterwards.
# Don't pick a plug-in from OBS's Filters dialog: in the Flatpak its list is empty and OBS saves a blank path.
# The eye icon on each filter turns it on and off.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$HOME/.vst"
gcc -O2 -fPIC -shared -fvisibility=hidden -Wall -Wextra -o "$HOME/.vst/HumNotch.so" "$HERE/hum_notch_vst.c" -lm
echo "Installed $HOME/.vst/HumNotch.so"
# A steady whine near 10 kHz that drifts between about 9.8 and 10.1 kHz, so the notch is wide (Q 4, about 2.5 kHz).
gcc -O2 -fPIC -shared -fvisibility=hidden -Wall -Wextra -DNOTCH_HZ=10000.0 -DNOTCH_Q=4.0 -DNOTCH_NAME='"Squeal Notch"' -DNOTCH_ID=0x5371754e \
  -o "$HOME/.vst/SquealNotch.so" "$HERE/tone_notch_vst.c" -lm
echo "Installed $HOME/.vst/SquealNotch.so"
# Fixed notches for two steady tones measured on the Independence Building microphone (Q 12, about 500 and 1100 Hz wide).
gcc -O2 -fPIC -shared -fvisibility=hidden -Wall -Wextra -DNOTCH_HZ=6381.0 -DNOTCH_Q=12.0 -DNOTCH_NAME='"Notch 6381 Hz"' -DNOTCH_ID=0x4e363338 \
  -o "$HOME/.vst/Notch6381.so" "$HERE/tone_notch_vst.c" -lm
echo "Installed $HOME/.vst/Notch6381.so"
gcc -O2 -fPIC -shared -fvisibility=hidden -Wall -Wextra -DNOTCH_HZ=13623.0 -DNOTCH_Q=12.0 -DNOTCH_NAME='"Notch 13623 Hz"' -DNOTCH_ID=0x4e313336 \
  -o "$HOME/.vst/Notch13623.so" "$HERE/tone_notch_vst.c" -lm
echo "Installed $HOME/.vst/Notch13623.so"
