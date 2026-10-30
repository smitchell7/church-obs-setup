#!/usr/bin/env bash
# Install OBS Studio (Flatpak) with the plugins this setup needs:
#   - DistroAV (NDI) from Flathub, plus the FFmpeg libraries NDI needs to decode HX2/HX3 cameras
#   - obs-ptz (PTZ Controls) as a Flatpak extension, from the bundle in vendor/
#     (built by https://github.com/smitchell7/obs-ptz, release v0.0.1-pre1)
#
# Usage:  sudo ./setup-obs-flatpak.sh
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

echo "==> [1/5] Installing Flatpak and adding the Flathub remote"
apt-get update -y
apt-get install -y flatpak
flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "==> [2/5] Installing OBS Studio and DistroAV (system-wide)"
flatpak install --system -y flathub "$OBS_ID"
flatpak install --system -y flathub "$OBS_ID.Plugin.DistroAV"

echo "==> [3/5] Letting OBS reach the local network and Avahi (mDNS camera discovery)"
flatpak override --system --share=network "$OBS_ID"
flatpak override --system --system-talk-name=org.freedesktop.Avahi "$OBS_ID"

echo "==> [4/5] Installing obs-ptz (PTZ Controls) from the bundled Flatpak"
BUNDLE="${PTZ_BUNDLE:-}"
if [ -z "$BUNDLE" ]; then
  BUNDLE=$(ls "$SCRIPT_DIR"/vendor/$PTZ_ASSET 2>/dev/null | tail -n1 || true)
fi
[ -f "$BUNDLE" ] || { echo "No obs-ptz bundle found in $SCRIPT_DIR/vendor; set PTZ_BUNDLE=/path/to/file" >&2; exit 1; }
flatpak install --system -y --bundle "$BUNDLE"

echo "==> [5/5] Putting the NDI HX decoder libraries where OBS can find them"
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

SCHEMA_FILE=/usr/share/glib-2.0/schemas/50_stake_defaults.gschema.override
if [ -f "$SCHEMA_FILE" ] && ! grep -q 'com.obsproject.Studio.desktop' "$SCHEMA_FILE"; then
  echo "==> Adding OBS to the GNOME dock favourites"
  sed -i "s/'org.gnome.Terminal.desktop'\]/'com.obsproject.Studio.desktop', 'org.gnome.Terminal.desktop']/" "$SCHEMA_FILE"
  glib-compile-schemas /usr/share/glib-2.0/schemas/
fi

echo "==> Done. Start OBS from the app menu or: flatpak run $OBS_ID"
