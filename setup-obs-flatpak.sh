#!/usr/bin/env bash
# Install OBS Studio (Flatpak) with the plugins this setup needs:
#   - DistroAV (NDI) from Flathub, plus the FFmpeg libraries NDI needs to decode HX2/HX3 cameras
#   - obs-ptz (PTZ Controls) as a Flatpak extension, from the bundle in vendor/
#     (built by https://github.com/smitchell7/obs-ptz, release v0.0.1-pre1)
#
# Usage:  sudo ./setup-obs-flatpak.sh [--install] [--config=NAME | --no-config] [--pin-dock | --no-pin-dock]
# Safe to run again at any time. By default it installs no software and only refreshes the OBS
# configuration (scenes, audio, Zoom microphone).
#   --install                   also install or update the software (OBS, DistroAV, obs-ptz, NDI
#                               decoder libraries); needed on a new computer
#   --config=NAME / --no-config  install the OBS scenes and camera setup in configs/NAME
#                               (without either, it asks when run in a terminal)
#   --pin-dock / --no-pin-dock  answer the "add OBS to the dock?" question up front
#                               (without either, it asks when run in a terminal)
# The user to configure is whoever ran sudo; override with TARGET_USER=name.
# PTZ_BUNDLE=/path/to/file.flatpak uses a different obs-ptz bundle than vendor/.
set -euo pipefail

OBS_ID=com.obsproject.Studio
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PTZ_ASSET='obs-ptz-*-flatpak-x86_64.flatpak'
# NDI's libndi loads FFmpeg 7.1 builds named libavcodec-ndi.so.61 / libavutil-ndi.so.59.
# The DistroAV extension does not ship them, so HX sources show black video with
# "NDI video decoder not found". We borrow stock FFmpeg 7.1 from the 25.08 runtime.
FFMPEG_RUNTIME_BRANCH=25.08
CODECS_BRANCH=25.08-extra

PIN_DOCK=ask
CONFIG_CHOICE=ask
INSTALL=no
DOCK_SCHEMA_FILE=${DOCK_SCHEMA_FILE:-/usr/share/glib-2.0/schemas/50_church_defaults.gschema.override}
for arg in "$@"; do
  case "$arg" in
    --pin-dock) PIN_DOCK=yes ;;
    --no-pin-dock) PIN_DOCK=no ;;
    --config=*) CONFIG_CHOICE=${arg#--config=} ;;
    --no-config) CONFIG_CHOICE=none ;;
    --install) INSTALL=yes ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo $0" >&2
  exit 1
fi

TARGET_USER="${TARGET_USER:-${SUDO_USER:-}}"
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = root ]; then
  echo "Run this with sudo from the broadcast user's session, or set TARGET_USER=name." >&2
  exit 1
fi
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
[ -d "$TARGET_HOME" ] || { echo "No home directory for $TARGET_USER" >&2; exit 1; }
as_user() { sudo -u "$TARGET_USER" -H "$@"; }

if [ "$INSTALL" != yes ]; then
  echo "==> Not installing software (add --install to install or update it)"
else
echo "==> [1/6] Installing Flatpak and adding the Flathub remote"
apt-get update -y
apt-get install -y flatpak python3-pil curl pulseaudio-utils
flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "==> [2/6] Installing OBS Studio and DistroAV (system-wide)"
# --or-update installs what is missing and updates what is already there
flatpak install --system -y --or-update flathub "$OBS_ID"
flatpak install --system -y --or-update flathub "$OBS_ID.Plugin.DistroAV"

echo "==> [3/6] Letting OBS reach the local network and Avahi (mDNS camera discovery)"
flatpak override --system --share=network "$OBS_ID"
flatpak override --system --system-talk-name=org.freedesktop.Avahi "$OBS_ID"

echo "==> [4/6] Installing obs-ptz (PTZ Controls) from the bundled Flatpak"
BUNDLE="${PTZ_BUNDLE:-}"
if [ -z "$BUNDLE" ]; then
  BUNDLE=$(ls "$SCRIPT_DIR"/vendor/$PTZ_ASSET 2>/dev/null | tail -n1 || true)
fi
[ -f "$BUNDLE" ] || { echo "No obs-ptz bundle found in $SCRIPT_DIR/vendor; set PTZ_BUNDLE=/path/to/file" >&2; exit 1; }
# Reinstalling an unchanged bundle fails, so remember which one is installed.
BUNDLE_STAMP=/var/lib/church-obs-ptz-bundle.sha256
BUNDLE_SUM=$(sha256sum "$BUNDLE" | cut -d' ' -f1)
if [ "$(cat "$BUNDLE_STAMP" 2>/dev/null || true)" = "$BUNDLE_SUM" ]; then
  echo "obs-ptz is already installed from this bundle."
else
  flatpak install --system -y --bundle "$BUNDLE"
  echo "$BUNDLE_SUM" > "$BUNDLE_STAMP"
fi

echo "==> [5/6] Putting the NDI HX decoder libraries where OBS can find them"
flatpak install --system -y --or-update flathub \
  "org.freedesktop.Platform//$FFMPEG_RUNTIME_BRANCH" \
  "org.freedesktop.Platform.codecs-extra//$CODECS_BRANCH"
CODECS=$(flatpak info --system --show-location org.freedesktop.Platform.codecs-extra "$CODECS_BRANCH")/files/lib
PLATFORM=$(flatpak info --system --show-location org.freedesktop.Platform "$FFMPEG_RUNTIME_BRANCH")/files/lib/x86_64-linux-gnu
NDI_LIBS="$TARGET_HOME/.var/app/$OBS_ID/data/ndi-libs"
as_user mkdir -p "$NDI_LIBS"

install_lib() { # source-file dest-name
  cp -L "$1" "$NDI_LIBS/$2"
  chown "$TARGET_USER:$TARGET_USER" "$NDI_LIBS/$2"
  chmod 755 "$NDI_LIBS/$2"
}
install_lib "$CODECS/libavcodec.so.61" libavcodec.so.61
install_lib "$CODECS/libavcodec.so.61" libavcodec-ndi.so.61
install_lib "$CODECS/libavutil.so.59" libavutil.so.59
install_lib "$CODECS/libavutil.so.59" libavutil-ndi.so.59
install_lib "$CODECS/libswresample.so.5" libswresample.so.5
# libavcodec.so.61 depends on these, which newer OBS runtimes don't provide
for lib in libvpx.so.11 libjxl.so.0.11 libjxl_threads.so.0.11 libjxl_cms.so.0.11 libSvtAv1Enc.so.3; do
  install_lib "$PLATFORM/$lib" "$lib"
done
as_user flatpak override --user --env=LD_LIBRARY_PATH="$NDI_LIBS" "$OBS_ID"

# Every library we copied must resolve inside the sandbox, otherwise NDI fails silently.
MISSING=$(as_user flatpak run --command=sh "$OBS_ID" -c \
  "cd '$NDI_LIBS' && for f in *.so*; do ldd ./\$f | grep 'not found'; done" || true)
if [ -n "$MISSING" ]; then
  echo "WARNING: NDI HX decoding will not work, unresolved libraries:" >&2
  echo "$MISSING" >&2
fi
fi # --install

# OBS scene collection and camera setup (configs/<name>/: single-camera or dual-camera).
echo "==> Choosing the OBS configuration"
mapfile -t CONFIGS < <(cd "$SCRIPT_DIR/configs" 2>/dev/null && ls -d */ 2>/dev/null | tr -d / || true)
if [ "$CONFIG_CHOICE" = ask ]; then
  if [ "${#CONFIGS[@]}" -eq 0 ]; then
    CONFIG_CHOICE=none
  elif [ -t 0 ]; then
    echo "Which camera setup should be installed?"
    select choice in "${CONFIGS[@]}" "none (set OBS up by hand)"; do
      case "$choice" in
        "") echo "Pick a number from the list." ;;
        none*) CONFIG_CHOICE=none; break ;;
        *) CONFIG_CHOICE=$choice; break ;;
      esac
    done
  else
    echo "No --config given and not running in a terminal; skipping the OBS configuration."
    CONFIG_CHOICE=none
  fi
fi
if [ "$CONFIG_CHOICE" != none ]; then
  CONFIG_SRC="$SCRIPT_DIR/configs/$CONFIG_CHOICE"
  [ -d "$CONFIG_SRC" ] || { echo "No such configuration: $CONFIG_CHOICE (have: ${CONFIGS[*]:-none})" >&2; exit 1; }
  SCENES_DIR="$TARGET_HOME/.var/app/$OBS_ID/config/obs-studio/basic/scenes"
  as_user mkdir -p "$SCENES_DIR"
  # Audio comes from a USB input (the Sound Blaster where there is one). Use AUDIO_DEVICE=name to force a
  # PulseAudio source, else pick the Sound Blaster, else any USB input, else the system default.
  if [ -z "${AUDIO_DEVICE:-}" ]; then
    TARGET_UID=$(id -u "$TARGET_USER")
    SOURCES=$(as_user env XDG_RUNTIME_DIR="/run/user/$TARGET_UID" pactl list short sources 2>/dev/null | cut -f2 | grep -v '\.monitor$' || true)
    AUDIO_DEVICE=$(grep -i 'sound_blaster' <<<"$SOURCES" | head -1 || true)
    [ -n "$AUDIO_DEVICE" ] || AUDIO_DEVICE=$(grep -i '^alsa_input\.usb' <<<"$SOURCES" | head -1 || true)
    [ -n "$AUDIO_DEVICE" ] || AUDIO_DEVICE=default
  fi
  echo "Audio input for OBS: $AUDIO_DEVICE (change it on the 'USB Audio' source in OBS if this is wrong)"
  if pgrep -u "$TARGET_USER" -f "$OBS_ID" >/dev/null; then
    echo "WARNING: OBS is running; it will overwrite these changes when it exits. Close OBS and run this again." >&2
  fi
  for f in "$CONFIG_SRC"/*.json; do
    dest="$SCENES_DIR/$(basename "$f")"
    rendered=$(mktemp)
    sed -e "s|@HOME@|$TARGET_HOME|g" -e "s|@AUDIO_DEVICE@|$AUDIO_DEVICE|g" "$f" > "$rendered"
    if [ -e "$dest" ] && cmp -s "$rendered" "$dest"; then
      echo "$(basename "$f") is already up to date."
    else
      [ -e "$dest" ] && as_user cp "$dest" "$dest.$(date +%Y%m%d-%H%M%S).bak"
      as_user tee "$dest" < "$rendered" >/dev/null
    fi
    rm -f "$rendered"
  done
  echo "Installed the '$CONFIG_CHOICE' scene collection. In OBS choose it from the Scene Collection menu."

  # Zoom audio: a virtual "OBS Mic (for Zoom)" microphone fed by OBS's audio monitoring (PipeWire's
  # PulseAudio layer is already on Ubuntu; only the pactl tool is added).
  PW_DIR="$TARGET_HOME/.config/pipewire/pipewire.conf.d"
  as_user mkdir -p "$PW_DIR"
  as_user cp "$SCRIPT_DIR/audio/obs-to-zoom.conf" "$PW_DIR/obs-to-zoom.conf"
  as_user python3 -I "$SCRIPT_DIR/tools/set-obs-monitor.py" "$TARGET_HOME/.var/app/$OBS_ID/config/obs-studio"
  echo "In Zoom choose the microphone 'OBS Mic (for Zoom)' (available after the next login or reboot)."
fi

# Sacrament scene music: piano accompaniment of "Bread of Life, Living Water" (church hymn
# recordings are free for home and church use). Not stored in the repo. Failure here is not fatal.
echo "==> [6/6] Installing the sacrament graphic and downloading the sacrament music"
MUSIC_PAGE='https://www.churchofjesuschrist.org/media/music/songs/bread-of-life-living-water?lang=eng'
MUSIC_FALLBACK='https://assets.churchofjesuschrist.org/a6/fa/a6fa4142ee3511eeab89eeeeac1ef623ccb828a4/bread_of_life_living_water.mp3'
MUSIC_DIR="$TARGET_HOME/Documents/sacrament"
MUSIC_FILE="$MUSIC_DIR/bread-of-life-living-water-piano.mp3"
as_user mkdir -p "$MUSIC_DIR"
# The painting (The Good Shepherd) is downloaded and the message is drawn on it; neither is kept in the repo.
if [ "$INSTALL" != yes ] && [ -s "$MUSIC_DIR/sacrament-graphic.png" ]; then
  echo "The sacrament graphic is already there."
else
  as_user python3 -I "$SCRIPT_DIR/tools/make-sacrament-graphic.py" --out "$MUSIC_DIR/sacrament-graphic.png" \
    || echo "WARNING: could not make the sacrament graphic; see tools/make-sacrament-graphic.py" >&2
fi
if [ ! -s "$MUSIC_FILE" ]; then
  # The page lists each recording's URL; pick the piano accompaniment (not guitar/vocal).
  MUSIC_URL=$(curl -fsSL -A 'Mozilla/5.0' "$MUSIC_PAGE" 2>/dev/null |
    python3 -c 'import re,sys; m=re.search(r"\"assetType\":\"AUDIO_ACCOMPANIMENT\",\"distributionUrl\":\"([^\"]+\.mp3)\"", sys.stdin.read()); print(m.group(1) if m else "")' || true)
  as_user mkdir -p "$MUSIC_DIR"
  as_user curl -fsSL -o "$MUSIC_FILE.part" "${MUSIC_URL:-$MUSIC_FALLBACK}" \
    && as_user mv "$MUSIC_FILE.part" "$MUSIC_FILE" \
    || { rm -f "$MUSIC_FILE.part"; echo "WARNING: could not download the sacrament music; fetch it by hand from $MUSIC_PAGE" >&2; }
fi

# Optional: pin OBS to the GNOME dock. Only possible where a schema override already
# sets favorite-apps (the church autoinstall creates one).
if [ -f "$DOCK_SCHEMA_FILE" ] && ! grep -q 'com.obsproject.Studio.desktop' "$DOCK_SCHEMA_FILE"; then
  if [ "$PIN_DOCK" = ask ] && [ -t 0 ]; then
    read -r -p "Add OBS to the GNOME dock favourites for new sessions? [y/N] " reply
    case "$reply" in [yY]*) PIN_DOCK=yes ;; *) PIN_DOCK=no ;; esac
  fi
  if [ "$PIN_DOCK" = yes ]; then
    echo "==> Adding OBS to the GNOME dock favourites"
    sed -i "s/'org.gnome.Terminal.desktop'\\]/'com.obsproject.Studio.desktop', 'org.gnome.Terminal.desktop']/" "$DOCK_SCHEMA_FILE"
    glib-compile-schemas /usr/share/glib-2.0/schemas/
  fi
fi

echo "==> Done. Start OBS from the app menu or: flatpak run $OBS_ID"
