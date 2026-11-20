#!/usr/bin/env bash
# Install OBS Studio (Flatpak) with the plugins this setup needs:
#   - DistroAV (NDI) from Flathub, plus the FFmpeg libraries NDI needs to decode HX2/HX3 cameras
#   - Downstream Keyer (overlay scenes kept on top of every scene) as a Flatpak extension, downloaded from
#     the newest release (pre-releases included) of https://github.com/harmanmj/obs-downstream-keyer,
#     or from Flathub when that fork has no Flatpak published
#   - obs-ptz (PTZ Controls) as a Flatpak extension, from the bundle in vendor/
#     (built by https://github.com/smitchell7/obs-ptz, release v0.0.1-pre1)
#
# Usage:  sudo ./setup-obs-flatpak.sh [--install] [--config=NAME | --no-config] [--pin-dock | --no-pin-dock]
# Safe to run again at any time. It first checks that OBS, DistroAV, Downstream Keyer, obs-ptz, the NDI
# decoder libraries and the system tools are installed and installs only what is missing, then refreshes
# the OBS configuration (scenes, audio, Zoom microphone).
#   --install                   also update everything that is already installed (OBS, DistroAV,
#                               Downstream Keyer, obs-ptz, NDI decoder libraries)
#   --config=NAME / --no-config  every scene collection in obs-configuration/ is installed; NAME is the one OBS
#                               opens on (without either, it asks when run in a terminal);
#                               --no-config skips the OBS scenes and camera setup
#   --pin-dock / --no-pin-dock  accepted for older instructions and ignored: OBS is always pinned to the dock
# The user to configure is whoever ran sudo; override with TARGET_USER=name.
# PTZ_BUNDLE=/path/to/file.flatpak uses a different obs-ptz bundle than vendor/.
# DSK_REPO=owner/name downloads Downstream Keyer from a different GitHub repo's releases.
# DSK_BUNDLE=/path/to/file.flatpak installs Downstream Keyer from a local file instead of downloading it.
set -euo pipefail

OBS_ID=com.obsproject.Studio
DSK_ID=$OBS_ID.Plugin.DownstreamKeyer
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PTZ_ASSET='obs-ptz-*-flatpak-x86_64.flatpak'
DSK_ASSET='obs-downstream-keyer-*-flatpak-x86_64.flatpak'
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

# A checkout in the user's home folder belongs to the user, so `git pull` (and tools/obs-config-update.py)
# work without sudo. Older instructions cloned it with sudo, which left it owned by root; fix that here.
# A checkout elsewhere (the autoinstall's /opt/church-obs-setup) is left as it is.
case "$SCRIPT_DIR/" in
  "$TARGET_HOME"/*)
    if [ -d "$SCRIPT_DIR/.git" ] && [ -n "$(find "$SCRIPT_DIR" ! -user "$TARGET_USER" -print -quit 2>/dev/null)" ]; then
      echo "==> Giving $SCRIPT_DIR back to $TARGET_USER (it was partly owned by root)"
      chown -R "$TARGET_USER:$(id -gn "$TARGET_USER")" "$SCRIPT_DIR"
    fi
    ;;
esac

NDI_LIBS="$TARGET_HOME/.var/app/$OBS_ID/data/ndi-libs"
PTZ_STAMP=/var/lib/church-obs-ptz-bundle.sha256
DSK_STAMP=/var/lib/church-obs-dsk-bundle.sha256
# Downstream Keyer comes from the Flatpak attached to the newest release (pre-releases included) of DSK_REPO,
# a fork with features Flathub's lacks. DSK_BUNDLE=/path/to/file.flatpak uses a local file instead.
DSK_REPO="${DSK_REPO:-harmanmj/obs-downstream-keyer}"
DSK_BUNDLE="${DSK_BUNDLE:-}"
# DSK_SOURCE is one of: file (DSK_BUNDLE was given), release (downloaded from DSK_REPO), flathub (DSK_REPO has
# no Flatpak published), unknown (GitHub could not be reached, or curl is not installed yet)
DSK_SOURCE=unknown DSK_SUM= DSK_NAME=
DSK_TMP=$(mktemp -d)
trap 'rm -rf "$DSK_TMP"' EXIT
dsk_lookup() {
  if [ -n "$DSK_BUNDLE" ]; then
    [ -f "$DSK_BUNDLE" ] || { echo "No Downstream Keyer bundle at $DSK_BUNDLE" >&2; exit 1; }
    DSK_SOURCE=file DSK_NAME=$(basename "$DSK_BUNDLE")
  else
    command -v curl >/dev/null || return 0
    local json url
    json=$(curl -fsSL --max-time 30 -H 'Accept: application/vnd.github+json' \
      "https://api.github.com/repos/$DSK_REPO/releases?per_page=30") || return 0
    # Releases come newest first; take the first one with a matching Flatpak attached.
    url=$(printf '%s' "$json" | python3 -I -c '
import fnmatch, json, sys
for r in json.load(sys.stdin):
    if r.get("draft"):
        continue
    for a in r.get("assets", []):
        if fnmatch.fnmatch(a["name"], sys.argv[1]):
            print(a["browser_download_url"])
            sys.exit()
' "$DSK_ASSET") || return 0
    if [ -z "$url" ]; then DSK_SOURCE=flathub; return 0; fi
    DSK_NAME=${url##*/}
    curl -fsSL --max-time 300 -o "$DSK_TMP/$DSK_NAME" "$url" || return 0
    DSK_SOURCE=release DSK_BUNDLE="$DSK_TMP/$DSK_NAME"
  fi
  DSK_SUM=$(sha256sum "$DSK_BUNDLE" | cut -d' ' -f1)
}
dsk_lookup

# What is missing? Each piece is installed when it is missing; --install also updates what is there.
NEED_APT=0 NEED_OBS=0 NEED_DISTROAV=0 NEED_DSK=0 NEED_PTZ=0 NEED_NDI=0
for cmd in flatpak curl pactl ffmpeg gcc git zenity; do command -v "$cmd" >/dev/null || NEED_APT=1; done
python3 -c 'import PIL' 2>/dev/null || NEED_APT=1
modinfo v4l2loopback >/dev/null 2>&1 || NEED_APT=1   # OBS Virtual Camera
if command -v flatpak >/dev/null; then
  flatpak info --system "$OBS_ID" >/dev/null 2>&1 || NEED_OBS=1
  flatpak info --system "$OBS_ID.Plugin.DistroAV" >/dev/null 2>&1 || NEED_DISTROAV=1
  if ! flatpak info --system "$DSK_ID" >/dev/null 2>&1; then
    NEED_DSK=1
  else
    case "$DSK_SOURCE" in
      # Installed, but not from this Flatpak (from Flathub, or an older release)
      file|release) [ "$(cat "$DSK_STAMP" 2>/dev/null || true)" = "$DSK_SUM" ] || NEED_DSK=1 ;;
      # The fork has no Flatpak published: a copy installed from one is replaced by Flathub's
      flathub) [ "$(flatpak info --system --show-origin "$DSK_ID" 2>/dev/null || true)" = flathub ] || NEED_DSK=1 ;;
      # GitHub could not be reached: keep what is installed
    esac
  fi
  flatpak list --system --columns=application 2>/dev/null | grep -qi 'ptz' || NEED_PTZ=1
  flatpak info --system "org.freedesktop.Platform//$FFMPEG_RUNTIME_BRANCH" >/dev/null 2>&1 || NEED_NDI=1
  flatpak info --system "org.freedesktop.Platform.codecs-extra//$CODECS_BRANCH" >/dev/null 2>&1 || NEED_NDI=1
else
  NEED_OBS=1 NEED_DISTROAV=1 NEED_DSK=1 NEED_PTZ=1 NEED_NDI=1
fi
for lib in libavcodec-ndi.so.61 libavutil-ndi.so.59 libswresample.so.5 libvpx.so.11; do
  [ -e "$NDI_LIBS/$lib" ] || NEED_NDI=1
done
want() { [ "$INSTALL" = yes ] || [ "$1" = 1 ]; }

echo "==> Checking the installed software"
status() { if [ "$2" = 1 ]; then echo "  $1: MISSING"; else echo "  $1: installed"; fi; }
status "system tools (flatpak, curl, pactl, ffmpeg, gcc, git, zenity, python3-pil, v4l2loopback)" "$NEED_APT"
status "OBS Studio" "$NEED_OBS"
status "DistroAV (NDI)" "$NEED_DISTROAV"
if [ "$DSK_SOURCE" = unknown ]; then
  echo "  (could not reach GitHub to check for Downstream Keyer releases in $DSK_REPO)"
fi
if [ "$NEED_DSK" = 1 ] && flatpak info --system "$DSK_ID" >/dev/null 2>&1; then
  if [ "$DSK_SOURCE" = flathub ]; then
    echo "  Downstream Keyer: installed from a bundle, but $DSK_REPO has no Flatpak release (will replace it with Flathub's)"
  else echo "  Downstream Keyer: installed, but not $DSK_NAME (will replace it)"; fi
else
  status "Downstream Keyer" "$NEED_DSK"
fi
status "obs-ptz (PTZ Controls)" "$NEED_PTZ"
status "NDI HX decoder libraries" "$NEED_NDI"
if [ "$INSTALL" = yes ]; then echo "  --install given: installing and updating everything"; fi

if want "$NEED_APT"; then
  echo "==> [1/6] Installing system tools"
  apt-get update -y
  apt-get install -y flatpak python3-pil curl pulseaudio-utils ffmpeg gcc git zenity v4l2loopback-dkms
fi
if [ "$INSTALL" = yes ] || [ "$NEED_OBS$NEED_DISTROAV$NEED_DSK$NEED_PTZ$NEED_NDI" != 00000 ]; then
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
if want "$NEED_DSK"; then
  # Adds the Downstream Keyer dock (Docks menu in OBS): scenes added there stay on top of every scene.
  # On a new computer curl was only just installed, so look again.
  if [ "$DSK_SOURCE" = unknown ]; then dsk_lookup; fi
  if [ "$DSK_SOURCE" = unknown ] && flatpak info --system "$DSK_ID" >/dev/null 2>&1; then
    echo "==> [2/6] Could not reach GitHub; keeping the Downstream Keyer that is installed"
  elif [ "$DSK_SOURCE" = file ] || [ "$DSK_SOURCE" = release ]; then
    echo "==> [2/6] Installing Downstream Keyer from $DSK_NAME"
    if flatpak info --system "$DSK_ID" >/dev/null 2>&1 &&
       [ "$(cat "$DSK_STAMP" 2>/dev/null || true)" = "$DSK_SUM" ]; then
      echo "Downstream Keyer is already installed from this Flatpak."
    else
      # Remove a copy from Flathub or from an older bundle first: --reinstall would keep its remote, and
      # Flathub refuses the unsigned bundle ("GPG verification enabled, but no signatures found").
      if flatpak info --system "$DSK_ID" >/dev/null 2>&1; then
        flatpak uninstall --system -y "$DSK_ID"
      fi
      flatpak install --system -y --bundle "$DSK_BUNDLE"
      echo "$DSK_SUM" > "$DSK_STAMP"
    fi
  else
    if [ "$DSK_SOURCE" = unknown ]; then
      echo "Could not download Downstream Keyer from $DSK_REPO; installing Flathub's for now (the next run replaces it)." >&2
    fi
    echo "==> [2/6] Installing Downstream Keyer from Flathub"
    if flatpak info --system "$DSK_ID" >/dev/null 2>&1 &&
       [ "$(flatpak info --system --show-origin "$DSK_ID")" != flathub ]; then
      flatpak install --system -y --reinstall flathub "$DSK_ID"   # replaces a copy from a bundle
      rm -f "$DSK_STAMP"
    else
      flatpak install --system -y --or-update flathub "$DSK_ID"
    fi
  fi
fi

if flatpak info --system "$OBS_ID" >/dev/null 2>&1; then
  echo "==> [3/6] Letting OBS reach the local network and Avahi (mDNS camera discovery)"
  flatpak override --system --share=network "$OBS_ID"
  flatpak override --system --system-talk-name=org.freedesktop.Avahi "$OBS_ID"
  # The notch filters on "USB Audio" are VST plug-ins in ~/.vst (built below). OBS's VST filter does not list
  # plug-ins from there inside the Flatpak unless VST_PATH says so, and then saves a blank plug-in path.
  # Set on every run (not only when the NDI libraries are installed), so existing computers get it too.
  as_user env flatpak override --user --env=VST_PATH="$TARGET_HOME/.vst" "$OBS_ID"
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
  # Through env: Flatpak refuses --user and "run" when sudo starts it directly.
  as_user env flatpak override --user --env=LD_LIBRARY_PATH="$NDI_LIBS" "$OBS_ID"

  # Every library we copied must resolve inside the sandbox, otherwise NDI fails silently.
  MISSING=$(as_user env flatpak run --command=sh "$OBS_ID" -c \
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

# OBS scene collections and camera setup (obs-configuration/<name>/, one folder per collection).
# Every collection is installed; CONFIG_CHOICE is the one OBS opens on ("keep" leaves that as it is).
echo "==> Choosing the default OBS scene collection"
mapfile -t FOUND < <(cd "$SCRIPT_DIR/obs-configuration" 2>/dev/null && ls -d */ 2>/dev/null | tr -d / || true)
# Menu order: the Sacrament collections (Alkire and Quail, Independence), then the Stake Meeting ones (same order), then Control, then anything else.
CONFIGS=()
for c in sacrament-alkire-and-quail sacrament-independence stake-meeting-alkire-and-quail stake-meeting-independence stake-meeting-independence-control; do
  [[ " ${FOUND[*]} " == *" $c "* ]] && CONFIGS+=("$c")
done
for c in "${FOUND[@]}"; do
  [[ " ${CONFIGS[*]} " == *" $c "* ]] || CONFIGS+=("$c")
done
# Which collection OBS opens on: asked every time, with the one OBS was using marked; Enter keeps it.
CURRENT_FILE=$(sed -n 's/^SceneCollectionFile=//p' "$TARGET_HOME/.var/app/$OBS_ID/config/obs-studio/user.ini" 2>/dev/null | head -1 || true)
CURRENT=${CURRENT_FILE%.json}
[[ -n "$CURRENT" && " ${CONFIGS[*]} " == *" $CURRENT "* ]] || CURRENT=
if [ "$CONFIG_CHOICE" = ask ]; then
  if [ "${#CONFIGS[@]}" -eq 0 ]; then
    CONFIG_CHOICE=none
  elif [ -t 0 ]; then
    echo "All the scene collections are installed. Which one should OBS open on?"
    for i in "${!CONFIGS[@]}"; do
      if [ "${CONFIGS[$i]}" = "$CURRENT" ]; then echo "  $((i + 1))) ${CONFIGS[$i]}   (current)"; else echo "  $((i + 1))) ${CONFIGS[$i]}"; fi
    done
    while :; do
      if [ -n "$CURRENT" ]; then read -r -p "Number (Enter keeps $CURRENT): " n; else read -r -p "Number: " n; fi
      if [ -z "$n" ] && [ -n "$CURRENT" ]; then echo "Keeping $CURRENT."; CONFIG_CHOICE=keep; break; fi
      if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#CONFIGS[@]}" ]; then CONFIG_CHOICE=${CONFIGS[$((n - 1))]}; break; fi
      echo "Pick a number from the list."
    done
  elif [ -n "$CURRENT" ]; then
    echo "Keeping the scene collection OBS was using ($CURRENT_FILE). Use --config=NAME to change it."
    CONFIG_CHOICE=keep
  else
    echo "No --config given and not running in a terminal; installing the scene collections without changing which one OBS opens on."
    CONFIG_CHOICE=keep
  fi
fi
if [ "$CONFIG_CHOICE" != none ]; then
  if [ "$CONFIG_CHOICE" != keep ] && [ ! -d "$SCRIPT_DIR/obs-configuration/$CONFIG_CHOICE" ]; then
    echo "No such configuration: $CONFIG_CHOICE (have: ${CONFIGS[*]:-none})" >&2; exit 1
  fi
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
  # The hum notch is an OBS filter on "USB Audio" (the HumNotch VST, built below), so OBS records the plain
  # hardware microphone. NOTCH=1 switches to the always-on PipeWire filter (audio/hum-notch.conf) instead;
  # don't use both, or the hum is filtered twice.
  if [ "${NOTCH:-0}" = 1 ] && [ "$AUDIO_DEVICE" != default ]; then AUDIO_DEVICE=hum_notch; fi
  echo "Audio input for OBS: $AUDIO_DEVICE (hardware: $HW_AUDIO_DEVICE; change it on the 'USB Audio' source in OBS if this is wrong)"
  if pgrep -u "$TARGET_USER" -f "$OBS_ID" >/dev/null; then
    echo "WARNING: OBS is running; it will overwrite these changes when it exits. Close OBS and run this again." >&2
  fi
  for f in "$SCRIPT_DIR"/obs-configuration/*/*.json; do
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
  echo "Installed the scene collections: ${CONFIGS[*]}."

  # The notch filters on both collections' "USB Audio" source (HumNotch, SquealNotch, Notch6381, Notch13623):
  # small VST 2.x plugins built into ~/.vst/.
  if command -v gcc >/dev/null 2>&1; then
    as_user bash "$SCRIPT_DIR/tools/hum-notch-vst/build.sh" || echo "WARNING: could not build the HumNotch VST; the filter on 'USB Audio' will not load." >&2
  else
    echo "WARNING: gcc is missing, so the HumNotch VST was not built (sudo apt-get install -y gcc, then run this again)." >&2
  fi

  # Zoom audio: a virtual "OBS Mic (for Zoom)" microphone fed by OBS's audio monitoring (PipeWire's
  # PulseAudio layer is already on Ubuntu; only the pactl tool is added).
  PW_DIR="$TARGET_HOME/.config/pipewire/pipewire.conf.d"
  PWP_DIR="$TARGET_HOME/.config/pipewire/pipewire-pulse.conf.d"
  PW_BEFORE=$(cat "$PW_DIR/obs-to-zoom.conf" "$PW_DIR/hum-notch.conf" "$PWP_DIR/obs-mic.conf" 2>/dev/null | md5sum || true)  # not there on a first run
  as_user mkdir -p "$PW_DIR" "$PWP_DIR"
  as_user cp "$SCRIPT_DIR/audio/obs-to-zoom.conf" "$PW_DIR/obs-to-zoom.conf"
  as_user cp "$SCRIPT_DIR/audio/obs-mic.conf" "$PWP_DIR/obs-mic.conf"
  # 60/120/180 Hz hum notch on the hardware microphone (see audio/hum-notch.conf).
  if [ "$AUDIO_DEVICE" = hum_notch ]; then
    sed "s|@AUDIO_DEVICE@|$HW_AUDIO_DEVICE|g" "$SCRIPT_DIR/audio/hum-notch.conf" | as_user tee "$PW_DIR/hum-notch.conf" >/dev/null
  else
    rm -f "$PW_DIR/hum-notch.conf"
  fi
  PW_AFTER=$(cat "$PW_DIR/obs-to-zoom.conf" "$PW_DIR/hum-notch.conf" "$PWP_DIR/obs-mic.conf" 2>/dev/null | md5sum || true)
  as_user python3 -I "$SCRIPT_DIR/tools/set-obs-monitor.py" "$TARGET_HOME/.var/app/$OBS_ID/config/obs-studio"
  # Video, on a first setup only, and skip OBS's Auto-Configuration Wizard.
  as_user python3 -I "$SCRIPT_DIR/tools/set-obs-video.py" "$TARGET_HOME/.var/app/$OBS_ID/config/obs-studio" --if-first-setup
  # Remote control: OBS's WebSocket server on port 4455, on by default, password from OBS_WEBSOCKET_PASSWORD.
  as_user env OBS_WEBSOCKET_PASSWORD="${OBS_WEBSOCKET_PASSWORD:-2ne2-14}" python3 -I "$SCRIPT_DIR/tools/set-obs-websocket.py" "$TARGET_HOME/.var/app/$OBS_ID/config/obs-studio"
  # The window layout, with the PTZ Controls dock in place.
  # and studio mode on.
  as_user python3 -I "$SCRIPT_DIR/tools/set-obs-docks.py" "$TARGET_HOME/.var/app/$OBS_ID/config/obs-studio"
  # Open OBS on the chosen default scene collection.
  if [ "$CONFIG_CHOICE" != keep ]; then
    as_user python3 -I "$SCRIPT_DIR/tools/set-obs-collection.py" "$TARGET_HOME/.var/app/$OBS_ID/config/obs-studio" "$SCRIPT_DIR/obs-configuration/$CONFIG_CHOICE"/*.json
  fi
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
  echo "speakers (never 'OBS Monitoring (not for Zoom)'), and Original sound for musicians on; see docs/technical-reference.md."
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

# The "OBS Configuration Reset" button (tools/obs-config-reset-button/button.sh): runs as the user, downloads the latest version
# of their copy of this repository with git and runs tools/obs-config-update.py. It needs a copy the user owns, so
# that git can update it without sudo: this one when it is in their home folder (~/church-obs-setup), else
# ~/church-obs-setup if it exists (e.g. on computers set up by the autoinstall, which runs from /opt).
BUTTON_DIR=
case "$SCRIPT_DIR/" in "$TARGET_HOME"/*) BUTTON_DIR=$SCRIPT_DIR ;; esac
[ -n "$BUTTON_DIR" ] || { [ -d "$TARGET_HOME/church-obs-setup/.git" ] && BUTTON_DIR="$TARGET_HOME/church-obs-setup"; }
if [ -n "$BUTTON_DIR" ] && [ -f "$BUTTON_DIR/tools/obs-config-reset-button/button.sh" ]; then
  echo "==> Adding the OBS Configuration Reset button (runs $BUTTON_DIR/tools/obs-config-reset-button/button.sh)"
  BUTTON_ICON=/usr/share/icons/hicolor/scalable/apps/church-obs-config-update.svg
  install -D -m 644 "$SCRIPT_DIR/tools/obs-config-reset-button/icon.svg" "$BUTTON_ICON"
  command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t /usr/share/icons/hicolor || true
  cat > /usr/share/applications/church-obs-config-update.desktop <<EOF
[Desktop Entry]
Type=Application
Name=OBS Configuration Reset
Comment=Get the latest scene collections and put the OBS configuration back to the church setup
Exec=bash "$BUTTON_DIR/tools/obs-config-reset-button/button.sh"
Icon=$BUTTON_ICON
Terminal=false
Categories=AudioVideo;
EOF
else
  rm -f /usr/share/applications/church-obs-config-update.desktop
  echo "WARNING: no copy of this repository in $TARGET_HOME (clone it to ~/church-obs-setup and run this again)," \
    "so the OBS Configuration Reset button was not added." >&2
fi

# OBS is always pinned to the GNOME dock, with the OBS Configuration Reset button next to it: in the user's own
# favourites (tools/set-obs-dock-pin.py, which needs their desktop session), and in the system default where a
# schema override sets one (the church autoinstall creates it), for when nobody is logged in yet.
echo "==> Pinning OBS to the GNOME dock"
PIN_RT="/run/user/$(id -u "$TARGET_USER")"
if [ -S "$PIN_RT/bus" ]; then
  as_user env XDG_RUNTIME_DIR="$PIN_RT" DBUS_SESSION_BUS_ADDRESS="unix:path=$PIN_RT/bus" \
    python3 -I "$SCRIPT_DIR/tools/set-obs-dock-pin.py" || echo "WARNING: could not pin OBS to the dock." >&2
else
  echo "$TARGET_USER is not logged in; OBS will be pinned on the next setup or update run from their session."
fi
if [ -f "$DOCK_SCHEMA_FILE" ]; then
  DOCK_APPS=(com.obsproject.Studio.desktop)
  [ -f /usr/share/applications/church-obs-config-update.desktop ] && DOCK_APPS+=(church-obs-config-update.desktop)
  for app in "${DOCK_APPS[@]}"; do
    grep -q "$app" "$DOCK_SCHEMA_FILE" \
      || sed -i "s/'org.gnome.Terminal.desktop'\\]/'$app', 'org.gnome.Terminal.desktop']/" "$DOCK_SCHEMA_FILE"
  done
  glib-compile-schemas /usr/share/glib-2.0/schemas/
fi

echo "==> Done. Start OBS from the app menu or: flatpak run $OBS_ID"
