#!/usr/bin/env bash
# Install OBS Studio (Flatpak) with the plugins this setup needs:
#   - DistroAV (NDI) from Flathub, plus the FFmpeg libraries NDI needs to decode HX2/HX3 cameras
#   - obs-ptz (PTZ Controls) as a Flatpak extension, from the bundle in vendor/
#     (built by https://github.com/smitchell7/obs-ptz, release v0.0.1-pre1)
#
# Usage:  sudo ./setup-obs-flatpak.sh [--install] [--config=NAME | --no-config] [--pin-dock | --no-pin-dock]
# Safe to run again at any time. It first checks that OBS, DistroAV, obs-ptz, the NDI decoder
# libraries and the system tools are installed and installs only what is missing, then refreshes the
# OBS configuration (scenes, audio, Zoom microphone).
#   --install                   also update everything that is already installed (OBS, DistroAV,
#                               obs-ptz, NDI decoder libraries)
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

NDI_LIBS="$TARGET_HOME/.var/app/$OBS_ID/data/ndi-libs"
PTZ_STAMP=/var/lib/church-obs-ptz-bundle.sha256

# What is missing? Each piece is installed when it is missing; --install also updates what is there.
NEED_APT=0 NEED_OBS=0 NEED_DISTROAV=0 NEED_PTZ=0 NEED_NDI=0
for cmd in flatpak curl pactl ffmpeg; do command -v "$cmd" >/dev/null || NEED_APT=1; done
python3 -c 'import PIL' 2>/dev/null || NEED_APT=1
modinfo v4l2loopback >/dev/null 2>&1 || NEED_APT=1   # OBS Virtual Camera
if command -v flatpak >/dev/null; then
  flatpak info --system "$OBS_ID" >/dev/null 2>&1 || NEED_OBS=1
  flatpak info --system "$OBS_ID.Plugin.DistroAV" >/dev/null 2>&1 || NEED_DISTROAV=1
  flatpak list --system --columns=application 2>/dev/null | grep -qi 'ptz' || NEED_PTZ=1
  flatpak info --system "org.freedesktop.Platform//$FFMPEG_RUNTIME_BRANCH" >/dev/null 2>&1 || NEED_NDI=1
  flatpak info --system "org.freedesktop.Platform.codecs-extra//$CODECS_BRANCH" >/dev/null 2>&1 || NEED_NDI=1
else
  NEED_OBS=1 NEED_DISTROAV=1 NEED_PTZ=1 NEED_NDI=1
fi
for lib in libavcodec-ndi.so.61 libavutil-ndi.so.59 libswresample.so.5 libvpx.so.11; do
  [ -e "$NDI_LIBS/$lib" ] || NEED_NDI=1
done
want() { [ "$INSTALL" = yes ] || [ "$1" = 1 ]; }

echo "==> Checking the installed software"
status() { if [ "$2" = 1 ]; then echo "  $1: MISSING"; else echo "  $1: installed"; fi; }
status "system tools (flatpak, curl, pactl, ffmpeg, python3-pil, v4l2loopback)" "$NEED_APT"
status "OBS Studio" "$NEED_OBS"
status "DistroAV (NDI)" "$NEED_DISTROAV"
status "obs-ptz (PTZ Controls)" "$NEED_PTZ"
status "NDI HX decoder libraries" "$NEED_NDI"
if [ "$INSTALL" = yes ]; then echo "  --install given: installing and updating everything"; fi

if want "$NEED_APT"; then
  echo "==> [1/6] Installing system tools"
  apt-get update -y
  apt-get install -y flatpak python3-pil curl pulseaudio-utils ffmpeg v4l2loopback-dkms
fi
if [ "$INSTALL" = yes ] || [ "$NEED_OBS$NEED_DISTROAV$NEED_PTZ$NEED_NDI" != 0000 ]; then
  flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
fi

if want "$NEED_OBS"; then
  echo "==> [2/6] Installing OBS Studio (system-wide)"
  # --or-update installs what is missing and updates what is already there
  flatpak install --system -y --or-update flathub "$OBS_ID"
fi
if want "$NEED_DISTROAV"; then
  echo "==> [2/6] Installing DistroAV (NDI)"
  flatpak install --system -y --or-update flathub "$OBS_ID.Plugin.DistroAV"
fi

if flatpak info --system "$OBS_ID" >/dev/null 2>&1; then
  echo "==> [3/6] Letting OBS reach the local network and Avahi (mDNS camera discovery)"
  flatpak override --system --share=network "$OBS_ID"
  flatpak override --system --system-talk-name=org.freedesktop.Avahi "$OBS_ID"
fi

if want "$NEED_PTZ"; then
  echo "==> [4/6] Installing obs-ptz (PTZ Controls) from the bundled Flatpak"
  BUNDLE="${PTZ_BUNDLE:-}"
  if [ -z "$BUNDLE" ]; then
    BUNDLE=$(ls "$SCRIPT_DIR"/vendor/$PTZ_ASSET 2>/dev/null | tail -n1 || true)
  fi
  [ -f "$BUNDLE" ] || { echo "No obs-ptz bundle found in $SCRIPT_DIR/vendor; set PTZ_BUNDLE=/path/to/file" >&2; exit 1; }
  # Reinstalling an unchanged bundle fails, so remember which one is installed.
  BUNDLE_SUM=$(sha256sum "$BUNDLE" | cut -d' ' -f1)
  if [ "$NEED_PTZ" = 0 ] && [ "$(cat "$PTZ_STAMP" 2>/dev/null || true)" = "$BUNDLE_SUM" ]; then
    echo "obs-ptz is already installed from this bundle."
  else
    flatpak install --system -y --bundle "$BUNDLE"
    echo "$BUNDLE_SUM" > "$PTZ_STAMP"
  fi
fi

if want "$NEED_NDI"; then
  echo "==> [5/6] Putting the NDI HX decoder libraries where OBS can find them"
  flatpak install --system -y --or-update flathub \
    "org.freedesktop.Platform//$FFMPEG_RUNTIME_BRANCH" \
    "org.freedesktop.Platform.codecs-extra//$CODECS_BRANCH"
  CODECS=$(flatpak info --system --show-location org.freedesktop.Platform.codecs-extra "$CODECS_BRANCH")/files/lib
  PLATFORM=$(flatpak info --system --show-location org.freedesktop.Platform "$FFMPEG_RUNTIME_BRANCH")/files/lib/x86_64-linux-gnu
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
fi

# OBS Virtual Camera (the video Zoom picks up). It needs the v4l2loopback kernel module; when the module is
# not loaded, OBS loads it with pkexec, which asks for an admin password every time. Load it at boot, with the
# options OBS itself uses, so starting the virtual camera needs no password.
echo "==> Loading the virtual camera module at boot (no password prompt when starting OBS's Virtual Camera)"
cat > /etc/modprobe.d/obs-virtualcam.conf <<'EOF'
# OBS Virtual Camera (setup-obs-flatpak.sh): the options OBS passes when it loads the module itself.
options v4l2loopback exclusive_caps=1 card_label="OBS Virtual Camera"
EOF
echo v4l2loopback > /etc/modules-load.d/obs-virtualcam.conf
if ! modinfo v4l2loopback >/dev/null 2>&1; then
  echo "WARNING: the v4l2loopback module is not available for kernel $(uname -r); OBS's Virtual Camera will not work until it is (sudo apt install v4l2loopback-dkms, then reboot)." >&2
elif ! grep -q '^v4l2loopback ' /proc/modules; then
  modprobe v4l2loopback || echo "WARNING: could not load v4l2loopback now; it loads at the next boot." >&2
fi
if mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
  echo "NOTE: Secure Boot is on. If the virtual camera does not appear, the v4l2loopback module may need its signing key enrolled (see 'mokutil --import')." >&2
fi

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
    # Else any real input, by name: "default" could one day be OBS Mic, which would feed OBS back into itself.
    [ -n "$AUDIO_DEVICE" ] || AUDIO_DEVICE=$(grep '^alsa_input\.' <<<"$SOURCES" | head -1 || true)
    [ -n "$AUDIO_DEVICE" ] || AUDIO_DEVICE=default
  fi
  HW_AUDIO_DEVICE=$AUDIO_DEVICE
  # OBS records the hum-filtered copy of that microphone (audio/hum-notch.conf) unless NOTCH=0 or there is
  # no real hardware input to filter.
  if [ "${NOTCH:-1}" != 0 ] && [ "$AUDIO_DEVICE" != default ]; then AUDIO_DEVICE=hum_notch; fi
  echo "Audio input for OBS: $AUDIO_DEVICE (hardware: $HW_AUDIO_DEVICE; change it on the 'USB Audio' source in OBS if this is wrong)"
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
  PWP_DIR="$TARGET_HOME/.config/pipewire/pipewire-pulse.conf.d"
  PW_BEFORE=$(cat "$PW_DIR/obs-to-zoom.conf" "$PW_DIR/hum-notch.conf" "$PWP_DIR/obs-mic.conf" 2>/dev/null | md5sum)
  as_user mkdir -p "$PW_DIR" "$PWP_DIR"
  as_user cp "$SCRIPT_DIR/audio/obs-to-zoom.conf" "$PW_DIR/obs-to-zoom.conf"
  as_user cp "$SCRIPT_DIR/audio/obs-mic.conf" "$PWP_DIR/obs-mic.conf"
  # 60/120/180 Hz hum notch on the hardware microphone (see audio/hum-notch.conf).
  if [ "$AUDIO_DEVICE" = hum_notch ]; then
    sed "s|@AUDIO_DEVICE@|$HW_AUDIO_DEVICE|g" "$SCRIPT_DIR/audio/hum-notch.conf" | as_user tee "$PW_DIR/hum-notch.conf" >/dev/null
  else
    rm -f "$PW_DIR/hum-notch.conf"
  fi
  PW_AFTER=$(cat "$PW_DIR/obs-to-zoom.conf" "$PW_DIR/hum-notch.conf" "$PWP_DIR/obs-mic.conf" 2>/dev/null | md5sum)
  as_user python3 -I "$SCRIPT_DIR/tools/set-obs-monitor.py" "$TARGET_HOME/.var/app/$OBS_ID/config/obs-studio"
  # Remote control: OBS's WebSocket server on port 4455, on by default, password from OBS_WEBSOCKET_PASSWORD.
  as_user env OBS_WEBSOCKET_PASSWORD="${OBS_WEBSOCKET_PASSWORD:-2ne2-14}" python3 -I "$SCRIPT_DIR/tools/set-obs-websocket.py" "$TARGET_HOME/.var/app/$OBS_ID/config/obs-studio"
  # PipeWire reads its drop-ins at start. If the user is logged in and the files changed or Zoom cannot see
  # the microphone yet (source obs_mic), restart PipeWire so it takes effect now instead of after the next
  # login (audio drops briefly; close Zoom calls first).
  USER_RT="/run/user/$(id -u "$TARGET_USER")"
  user_pactl() { as_user env XDG_RUNTIME_DIR="$USER_RT" pactl "$@"; }
  if [ -S "$USER_RT/bus" ]; then
    if [ "$PW_BEFORE" != "$PW_AFTER" ] || ! user_pactl list short sources 2>/dev/null | cut -f2 | grep -qx obs_mic; then
      echo "Restarting PipeWire so the 'OBS Mic (for Zoom)' microphone is up to date (audio drops for a moment)"
      as_user env XDG_RUNTIME_DIR="$USER_RT" DBUS_SESSION_BUS_ADDRESS="unix:path=$USER_RT/bus" \
        systemctl --user restart pipewire pipewire-pulse wireplumber \
        || echo "NOTE: could not restart PipeWire; the microphone will appear after the next login or reboot." >&2
      for _ in 1 2 3 4 5 6 7 8 9 10; do user_pactl list short sources 2>/dev/null | cut -f2 | grep -qx obs_mic && break; sleep 1; done
    fi
    # OBS Mic must never be the system default microphone: OBS's USB Audio source (and anything else on
    # "default") would record OBS's own output and feed it back. Undo that if it was set.
    if [ "$(user_pactl get-default-source 2>/dev/null)" = obs_mic ]; then
      HW_MIC=$(user_pactl list short sources 2>/dev/null | cut -f2 | grep '^alsa_input\.' | head -1 || true)
      [ -n "$HW_MIC" ] && user_pactl set-default-source "$HW_MIC" && echo "Default microphone set back to $HW_MIC (OBS Mic must not be the default)"
    fi
  fi
  echo "In Zoom pick, by name: Microphone 'OBS Mic (for Zoom)' (not 'Same as System'), Speaker the computer's"
  echo "speakers (never 'OBS Monitoring (not for Zoom)'), and Original sound for musicians on; see the README."
fi

# Sacrament scene music: piano accompaniments of church hymns (free for home and church use),
# played as a looping playlist. Not stored in the repo. Failure here is not fatal.
echo "==> [6/6] Installing the sacrament graphic and building the sacrament music playlist"
MUSIC_DIR="$TARGET_HOME/Documents/sacrament"
as_user mkdir -p "$MUSIC_DIR"
# The painting (The Good Shepherd) is downloaded and the message is drawn on it; neither is kept in the repo.
if [ "$INSTALL" != yes ] && [ -s "$MUSIC_DIR/sacrament-graphic.png" ]; then
  echo "The sacrament graphic is already there."
else
  as_user python3 -I "$SCRIPT_DIR/tools/make-sacrament-graphic.py" --out "$MUSIC_DIR/sacrament-graphic.png" \
    || echo "WARNING: could not make the sacrament graphic; see tools/make-sacrament-graphic.py" >&2
fi
# The hymns listed in audio/sacrament-playlist.txt are downloaded and joined into one file that OBS loops.
as_user python3 -I "$SCRIPT_DIR/tools/make-sacrament-playlist.py" \
  --list "$SCRIPT_DIR/audio/sacrament-playlist.txt" --dir "$MUSIC_DIR" \
  || echo "WARNING: could not build the sacrament playlist; see tools/make-sacrament-playlist.py" >&2

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
