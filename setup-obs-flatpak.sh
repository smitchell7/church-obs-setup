#!/usr/bin/env bash
# Install OBS Studio (Flatpak) with the plugins this setup needs:
#   - DistroAV (NDI) from Flathub, plus the FFmpeg libraries NDI needs to decode HX2/HX3 cameras
#   - obs-ptz (PTZ Controls) as a Flatpak extension, from the bundle in vendor/
#     (built by https://github.com/smitchell7/obs-ptz, release v0.0.1-pre1)
#
# Usage:  sudo ./setup-obs-flatpak.sh [--pin-dock | --no-pin-dock]
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
DOCK_SCHEMA_FILE=${DOCK_SCHEMA_FILE:-/usr/share/glib-2.0/schemas/50_church_defaults.gschema.override}
for arg in "$@"; do
  case "$arg" in
    --pin-dock) PIN_DOCK=yes ;;
    --no-pin-dock) PIN_DOCK=no ;;
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

echo "==> [1/6] Installing Flatpak and adding the Flathub remote"
apt-get update -y
apt-get install -y flatpak
flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "==> [2/6] Installing OBS Studio and DistroAV (system-wide)"
flatpak install --system -y flathub "$OBS_ID"
flatpak install --system -y flathub "$OBS_ID.Plugin.DistroAV"

echo "==> [3/6] Letting OBS reach the local network and Avahi (mDNS camera discovery)"
flatpak override --system --share=network "$OBS_ID"
flatpak override --system --system-talk-name=org.freedesktop.Avahi "$OBS_ID"

echo "==> [4/6] Installing obs-ptz (PTZ Controls) from the bundled Flatpak"
BUNDLE="${PTZ_BUNDLE:-}"
if [ -z "$BUNDLE" ]; then
  BUNDLE=$(ls "$SCRIPT_DIR"/vendor/$PTZ_ASSET 2>/dev/null | tail -n1 || true)
fi
[ -f "$BUNDLE" ] || { echo "No obs-ptz bundle found in $SCRIPT_DIR/vendor; set PTZ_BUNDLE=/path/to/file" >&2; exit 1; }
flatpak install --system -y --bundle "$BUNDLE"

echo "==> [5/6] Putting the NDI HX decoder libraries where OBS can find them"
flatpak install --system -y flathub \
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

# Sacrament scene music: piano accompaniment of "Bread of Life, Living Water" (church hymn
# recordings are free for home and church use). Not stored in the repo. Failure here is not fatal.
echo "==> [6/6] Installing the sacrament graphic and downloading the sacrament music"
MUSIC_PAGE='https://www.churchofjesuschrist.org/media/music/songs/bread-of-life-living-water?lang=eng'
MUSIC_FALLBACK='https://assets.churchofjesuschrist.org/a6/fa/a6fa4142ee3511eeab89eeeeac1ef623ccb828a4/bread_of_life_living_water.mp3'
MUSIC_DIR="$TARGET_HOME/Documents/sacrament"
MUSIC_FILE="$MUSIC_DIR/bread-of-life-living-water-piano.mp3"
as_user mkdir -p "$MUSIC_DIR"
as_user cp "$SCRIPT_DIR/assets/sacrament-graphic.png" "$MUSIC_DIR/sacrament-graphic.png"
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
