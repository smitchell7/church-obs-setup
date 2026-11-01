#!/usr/bin/env bash
# Installs the 60/120/180/240 Hz hum notch (audio/hum-notch.conf) WITHOUT restarting PipeWire or touching
# OBS, so it is safe while OBS or Zoom is running. Run as the normal user (no sudo):
#   tools/install-hum-notch.sh [mic-source-name]     (list names: pactl list short sources)
# It (1) writes the drop-in so the filter is loaded at every future login and (2) loads it now.
# Afterwards, in OBS: USB Audio > Properties > Device = "USB Audio (hum filtered)" (a brief audio blip).
# Remove: rm ~/.config/pipewire/pipewire.conf.d/hum-notch.conf, switch OBS back, pkill -f 'pw-cli -m'.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
MIC=${1:-}
if [ -z "$MIC" ]; then   # same choice as setup-obs-flatpak.sh: Sound Blaster, else USB, else any real input
  S=$(pactl list short sources | cut -f2 | grep -v '\.monitor$')
  MIC=$(grep -i sound_blaster <<<"$S" | head -1 || true)
  [ -n "$MIC" ] || MIC=$(grep -i '^alsa_input\.usb' <<<"$S" | head -1 || true)
  [ -n "$MIC" ] || MIC=$(grep '^alsa_input\.' <<<"$S" | head -1 || true)
fi
[ -n "$MIC" ] || { echo "No microphone found; pass its name as an argument." >&2; exit 1; }
pactl list short sources | cut -f2 | grep -qx "$MIC" || { echo "No such source: $MIC" >&2; exit 1; }
echo "Filtering microphone: $MIC"
CONF="$HOME/.config/pipewire/pipewire.conf.d/hum-notch.conf"
mkdir -p "$(dirname "$CONF")"
sed "s|@AUDIO_DEVICE@|$MIC|g" "$HERE/audio/hum-notch.conf" > "$CONF"
if pactl list short sources | cut -f2 | grep -qx hum_notch; then echo "hum_notch is already running; drop-in installed, nothing to load now."; exit 0; fi
# Load now: pw-cli keeps the module only while it runs, so leave it running in the background.
ARGS=$(python3 -I -c "
import sys;s=open(sys.argv[1]).read();i=s.index('args = {')+7;j=s.rindex('}\n    }\n]');print(' '.join((s[i:j].strip()+'\n}').split()))" "$CONF")
(echo "load-module libpipewire-module-filter-chain $ARGS"; sleep infinity) | setsid nohup pw-cli -m >/dev/null 2>&1 &
for _ in 1 2 3 4 5 6 7 8 9 10; do pactl list short sources | cut -f2 | grep -qx hum_notch && break; sleep 1; done
pactl list short sources | cut -f2 | grep -qx hum_notch || { echo "The filter did not start." >&2; exit 1; }
echo "Running. In OBS set USB Audio > Properties > Device to 'USB Audio (hum filtered)'."
