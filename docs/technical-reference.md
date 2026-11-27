# Technical reference

How the setup and update scripts work, their options, and the details behind the audio routing, the notch filters
and the autoinstall. For an introduction and where to find things, see the [README](../README.md); for
step-by-step instructions, the [Ubuntu](../Ubuntu%20Install%20README.md) and
[Windows](../Windows%20Install%20README.md) install guides.

## Ubuntu setup (`setup-obs-flatpak.sh`)

```bash
sudo ./setup-obs-flatpak.sh             # new computer or later: install what is missing, refresh the configuration
sudo ./setup-obs-flatpak.sh --install   # also update the software that is already installed
```

The script can be run again at any time. It first checks that OBS, DistroAV, Downstream Keyer, obs-ptz, the NDI
decoder libraries and the system tools are installed and installs only what is missing (on an up-to-date
computer it installs nothing), then sets up the configuration (scenes, layout, audio, Zoom microphone). Every
scene file it replaces is saved as `*.bak` first.

Options: `--install` (also update what is already installed); `--config=FOLDER` (a collection folder in
`obs-configuration/`, e.g. `sacrament-independence`: the collection OBS opens on; without it, it asks in a terminal, with the current one marked and Enter keeping
it) or `--no-config` (skip the scene collections);
`--pin-dock` / `--no-pin-dock` (accepted for older instructions and ignored: OBS is always pinned). Environment: `TARGET_USER=name` (default: whoever ran
sudo), `AUDIO_DEVICE=name` (force the OBS audio input), `OBS_WEBSOCKET_PASSWORD` (see Remote control),
`PTZ_BUNDLE=/path/file.flatpak` (a different obs-ptz build), `DSK_REPO=owner/name` (download Downstream Keyer
from a different GitHub repo's releases), `DSK_BUNDLE=/path/file.flatpak` (install Downstream Keyer from a local
file instead), `NOTCH=1` (the optional PipeWire hum filter, below).

What it installs:

- OBS Studio, DistroAV (NDI) and the obs-ptz PTZ Controls extension, system-wide from Flathub, and the FFmpeg
  libraries NDI needs to decode HX2/HX3 cameras (without them, HX cameras show black video with "NDI video
  decoder not found"). OBS is allowed to reach the local network and Avahi (camera discovery).
- The obs-ptz Flatpak bundle is in `vendor/` (built from <https://github.com/smitchell7/obs-ptz>, a fork of
  <https://github.com/glikely/obs-ptz>, GPL-2.0; the source is in that repo). To use a different build, run
  `sudo PTZ_BUNDLE=/path/to/file.flatpak ./setup-obs-flatpak.sh`.
- Downstream Keyer is downloaded on each run from the newest release (pre-releases included) of
  <https://github.com/harmanmj/obs-downstream-keyer>, a fork of <https://github.com/exeldro/obs-downstream-keyer>
  (GPL-2.0), whose releases each attach `obs-downstream-keyer-<version>-flatpak-x86_64.flatpak`. It adds Load On
  Scene, which shows a keyer only on the program scenes you choose, and Go Live / Go to Preview controls that work
  with Studio Mode. A computer that has Flathub's Downstream Keyer, or an older release, is switched to the newest
  release on the next run; publishing a new release on the fork is all it takes to update. If the fork has no
  Flatpak published, Flathub's is used. If GitHub can't be reached, the installed copy is kept (or, if there is
  none, Flathub's is installed until the next run).
- The notch filter plugins, built into `~/.vst` (see Hum and tone filters).

What it sets up:

- **Scene collections:** every collection in `obs-configuration/`. It asks which one OBS opens on (a numbered
  menu) every time; the one OBS was using is marked (current), and Enter keeps it. Run without a terminal and
  without `--config`, it keeps the current collection (or leaves OBS's default as it is).
- **Window layout and Studio Mode:** `obs-configuration/obs-layout.ini` (`tools/set-obs-docks.py`): the docks with
  PTZ Controls in place (Downstream Keyer closed; open it from the Docks menu), side docks and the vertical mixer.
  Every run puts the layout back and turns Studio Mode on, so a dock closed or moved by accident is fixed.
- **Starting OBS maximized, on computers converted to X11 only.** Where the OBS Flatpak has an override that
  makes it run under X11 (`sockets=x11;!wayland` or `QT_QPA_PLATFORM=xcb`; the Independence building uses X11 so
  that OBS's full-screen projector works there),
  the first time OBS opens after a computer restart, its window doesn't open maximized, although OBS saved it
  maximized (seen on the three-screen Independence computer; harmanmj/church-obs-setup#4). This launcher is the
  fix; it is to be confirmed with the next update on that computer.
  There, setup installs `wmctrl` and `tools/set-obs-launcher.py` writes the user's own copy of OBS's app-menu
  entry (`~/.local/share/applications/com.obsproject.Studio.desktop`, so the dock icon, the menu and search use
  it) to start OBS through `tools/obs-launch.sh`, which waits for OBS's window and maximizes it where it is. An
  autostart entry for OBS, if there is one, is pointed at it too, keeping its original command so it can be put
  back. On every other computer nothing is installed or changed, and a launcher left from an earlier run (if the
  computer went back to Wayland) is removed. The configuration update does the same.
- **Video**, on a first setup only: a 1920x1080 canvas and output at 30 fps, recording quality "Same as stream",
  and OBS's Auto-Configuration Wizard skipped (`tools/set-obs-video.py` sets the video again).
- **Audio and Zoom**, **Virtual Camera** and **Remote control** (below).
- **Sacrament graphic and music** (below).
- **The GNOME dock:** OBS is always pinned (`tools/set-obs-dock-pin.py`): it is added to the user's own dock
  favourites if it is missing, keeping the others. That needs the user's desktop session, so if they aren't logged
  in it is pinned on the next run. Where the church autoinstall's schema override sets the default favourites,
  OBS is added there too, for new sessions.
- **The repo folder's owner:** it gives a checkout in the user's home folder (`~/church-obs-setup`) back to that
  user if any of it is owned by root. Older instructions cloned it with `sudo git clone`; nothing needs root
  ownership, and it stops `git pull` and `tools/obs-config-update.py` from working without sudo. A checkout
  elsewhere (the autoinstall's `/opt/church-obs-setup`, which only its first-boot service uses) is left as it is.

## Keeping computers up to date (`obs-config-update`)

`tools/obs-config-update.py` (Ubuntu) and `tools\obs-config-update.ps1` (Windows) put a computer's OBS
configuration back to this repo's version, without installing software and without sudo. Its job is to fix
changes made by accident, so it **resets everything to the repo** on every run:

- Every collection in `obs-configuration/` is rewritten from the repo: scenes that were removed come back, and
  edits made in OBS are undone. A collection that was removed is reinstalled. The replaced file is saved next to
  it as `NAME.json.<date-time>.bak`.
- The window layout is put back and Studio Mode is turned on.
- Audio monitoring is pointed back at what Zoom hears, and the WebSocket server is turned on.
- On Ubuntu, OBS is pinned to the dock again if someone unpinned it.

It keeps:

- **The devices picked in OBS**, by source name: the "USB Audio" microphone, the capture devices and the NDI
  senders (FreeShow and cameras). A new "USB Audio" gets the input the setup script would pick.
- **The collection OBS was using, if you want.** It asks which collection OBS opens on, with the current one marked;
  pressing Enter keeps it (or answer up front with `--default FOLDER` /
  `-Default FOLDER`).
- **The WebSocket password.**
- **The video settings**, which only the setup script sets, on a first setup.

**The OBS Configuration Reset button (Ubuntu).** `tools/obs-config-reset-button/button.sh` runs the update from the app menu or
the dock, as the user, without a password or a terminal (the windows are zenity dialogs):

1. It does nothing, with a message, when OBS is open, and a second click while it runs is ignored.
2. It downloads the latest version of its own copy of this repo (`git fetch`, then a fast-forward of the branch's
   upstream). With no network, it carries on with the version already there. If files in the copy were edited
   by hand and the update changes them too, so the download can't apply, it asks: "Set aside and update" runs
   `git stash` (the edits are kept, not deleted) and applies the update; "Keep them, don't update" carries on
   with the version already there. Hand edits to files the update doesn't touch don't stop it, so there's no
   question then. Changes made in OBS never count: OBS keeps its scenes in its own folder.
3. It asks which scene collection OBS opens on, in a list with the current one selected (the same list and order
   as the terminal menu, from `obs-config-update.py --list`). Cancel stops without changing anything.
4. It runs `obs-config-update.py --default FOLDER` in the background and shows the result, or the details when
   something failed. The output of the last run is in `~/.cache/church-obs-config-update.log`.

The setup script installs `git` and `zenity`, writes the app-menu entry
(`/usr/share/applications/church-obs-config-update.desktop`, with the icon `tools/obs-config-reset-button/icon.svg`) and pins it next to OBS (`tools/set-obs-dock-pin.py`,
which the update runs too). The button runs from the user's own copy of the repo, so git can update it without
sudo: the copy setup runs from when it is in the user's home folder, else `~/church-obs-setup` if it exists. Where
there is neither (a computer set up only by the autoinstall, which runs from `/opt/church-obs-setup`), setup says
so and doesn't add the button until `~/church-obs-setup` is cloned.

On Ubuntu it also builds any missing notch filter plugins and makes sure the OBS Flatpak can find them. On
Windows it copies them to `C:\Program Files\VSTPlugins` when run as administrator, and otherwise prints the
command to do it. Collections that aren't in the repo (made in OBS, or retired ones) are left alone.

## Audio, Zoom and remote control

- **Microphone:** video comes from the cameras (their own audio is not used). Audio comes from the "USB Audio"
  source, a USB input (the Sound Blaster where there is one), in every scene except Sacrament. The installer
  picks the Sound Blaster, else any USB input, else the system default (`AUDIO_DEVICE=name` forces one; at first
  boot there is no desktop session, so it usually falls back to default: set the device on the source in OBS).
  The Sacrament scene plays the sacrament music instead and has no microphone, so changing to it switches the
  Zoom audio from the USB input to the music, and changing back switches it again.
- **Zoom audio (Ubuntu):** OBS monitors its audio (the USB input and the sacrament music) into a virtual speaker
  that only OBS uses, "OBS Monitoring (not for Zoom)" (`audio/obs-to-zoom.conf`), and a virtual microphone, "OBS
  Mic (for Zoom)", carries it (`audio/obs-mic.conf`, a remap of the speaker's monitor). Never make that microphone
  the system default: OBS's "USB Audio" source (and anything else on "default") would then record OBS's own
  output and feed it back, which sounds like a tone or howl. Ubuntu already uses PipeWire, which speaks the
  PulseAudio protocol, so PulseAudio itself is not needed (the installer adds `pulseaudio-utils` for `pactl`).
  PipeWire only reads these files when it starts, so if the user is logged in the installer restarts PipeWire
  when they change (audio drops for a moment; not during a Zoom call); otherwise they apply after the next login.
  `tools/set-obs-monitor.py` points OBS's monitoring device at the speaker.
- **Monitoring:** both audio sources have monitoring set to "Monitor and Output". OBS 33 needs
  `monitoring_enabled: true` in the scene file as well as `monitoring_type: 2`; with only the type set, nothing is
  sent to Zoom. If Zoom hears nothing, check Edit > Advanced Audio Properties in OBS: "USB Audio" and "Sacrament
  Music" must say "Monitor and Output".
- **Zoom settings, once per computer** (Zoom keeps these itself, so the installer cannot set them): Settings >
  Audio: **Microphone** "OBS Mic (for Zoom)", picked by name (not "Same as System"); **Speaker** the computer's
  speakers or headphones, never "OBS Monitoring (not for Zoom)", which would send the meeting back into the
  microphone; under Music and Professional Audio, tick **Show in-meeting option to enable "Original sound for
  musicians"**, then in a meeting click **Original sound for musicians: Off** at the top left to turn it on
  (recent Zoom versions remember it; check at the start of each meeting). Without it Zoom's noise suppression
  chops up the music. Menu names vary a little between Zoom versions. If the option is missing, the Zoom
  account's web settings (zoom.us > Settings > Audio) must allow it. Camera: "OBS Virtual Camera".
- **Virtual Camera (Ubuntu):** OBS's Virtual Camera needs the `v4l2loopback` kernel module. When it is not
  loaded, OBS loads it itself with `pkexec`, which asks for an admin password every time. The installer installs
  `v4l2loopback-dkms` and loads the module at boot with OBS's own options (`/etc/modprobe.d/obs-virtualcam.conf`,
  `/etc/modules-load.d/obs-virtualcam.conf`), so Start Virtual Camera needs no password.
- **Remote control:** OBS's WebSocket server is switched on (port 4455, password required), on Ubuntu and
  Windows; the Stake Meeting control laptop connects to it. The password is `OBS_WEBSOCKET_PASSWORD` in
  `secrets.env` for the autoinstall, or the same variable when running a setup script by hand; if neither is
  set, the setup uses its built-in default. That default is in this public repo, so set your own for anything
  that matters. The update script keeps the password that is there. `tools/set-obs-websocket.py` and
  `tools\set-obs-websocket.ps1` do this.
- **Camera presets** are stored in the cameras: save positions in these slots on each camera so the scenes can
  recall them: 0 Pulpit, 1 Chorister, 2 Rostrum, 3 Full Room, 4 Piano, 5 Speaker Close-up, 6 Piano and Pulpit,
  7 Organ, 8 Choir.

## Sacrament graphic and music

- The sacrament background picture: `tools/make-sacrament-graphic.py` downloads *The Good Shepherd* from
  churchofjesuschrist.org and crops it; the message is OBS text layers in the scene; use `--image` for a
  different picture. It goes in `~/Documents/sacrament/`.
- The sacrament music playlist: the hymns listed in `audio/sacrament-playlist.txt` (one page name per line, in
  play order) are downloaded as piano accompaniments from churchofjesuschrist.org and joined with ffmpeg into
  `~/Documents/sacrament/sacrament-playlist.mp3`, which the Sacrament scene loops. To change the playlist, edit the
  list and run the setup script again; it downloads only what is new. The music is not stored in this repo.

## Windows setup (`setup-obs-windows.ps1`, backup)

One run installs everything and configures it. From an elevated PowerShell (right-click, Run as
administrator), signed in as the person who will use OBS:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1   # asks which collection OBS opens on (Enter keeps the current one)
```

The script can be downloaded on its own and run from anywhere: it installs Git (via `winget`), clones this
repo to `C:\church-obs-setup` (or switches it to the default branch and updates it with `git pull`), and carries
on from that checkout, so a computer always runs the current version. Run it again at any time to update; close
OBS first. It then:

- installs OBS Studio 33+ and the NDI Runtime (`winget`), and the latest DistroAV, Downstream Keyer and obs-ptz
  releases from GitHub. Downstream Keyer is the fork `harmanmj/obs-downstream-keyer` (pre-releases included);
  exeldro's release is used instead when the fork has no Windows installer or can't be reached, or always with
  `-DskRepo exeldro/obs-downstream-keyer`. obs-ptz is upstream `glikely/obs-ptz`, whose 1.0 betas use the same
  preset format as these collections; `-PtzInstaller C:\path\...-Installer.exe` uses another build;
- installs ffmpeg (`winget`, for the playlist) and **VB-Audio Virtual Cable**, the virtual microphone for Zoom.
  VB-CABLE is donationware with its own licence (<https://vb-audio.com/Services/licensing.htm>); its setup
  window opens: click "Install Driver" and accept. It needs a Windows restart: restart, then run the script
  again to finish;
- installs every scene collection in `obs-configuration\` (an existing file is saved as `*.bak`) and makes the
  chosen one the one OBS opens on (`-Config FOLDER`, e.g. `-Config sacrament-independence`, else it asks, with the
  current one marked and Enter keeping it; `-NoConfig` skips the collections). The "USB Audio" source
  becomes a Windows (WASAPI) input on the Sound Blaster, else a USB input, else (with a warning) another real
  input, never "NDI Webcam Audio", whose sound is poor; plug the USB input in before running it.
  `-AudioDevice "part of its name"` picks another;
- installs the notch filter plugins (prebuilt DLLs) to `C:\Program Files\VSTPlugins` and points the filters there;
- points OBS's audio monitoring at the cable's input, "CABLE Input (VB-Audio Virtual Cable)" (newer VB-CABLE versions: "Speakers (VB-Audio Virtual Cable)") (`tools\set-obs-monitor.ps1`), so the
  USB input and the sacrament music go to Zoom: in Zoom pick the microphone **CABLE Output (VB-Audio Virtual
  Cable)**;
- on a first setup, sets OBS's video to a 1920x1080 canvas and output at 30 fps, with recording quality "Same
  as stream", and skips its Auto-Configuration Wizard (`tools\set-obs-video.ps1` sets the video again);
- installs the OBS window layout (`tools\set-obs-docks.ps1`) and turns Studio Mode on, on every run;
- turns on OBS's WebSocket server (`tools\set-obs-websocket.ps1`, password from `$env:OBS_WEBSOCKET_PASSWORD`,
  else the same default as Ubuntu), so a Windows laptop can stand in as the main OBS for the control laptop;
- adds a firewall rule for NDI, makes the sacrament graphic, and builds the sacrament playlist from
  `audio\sacrament-playlist.txt` (`tools\make-sacrament-playlist.ps1`) in `Documents\sacrament`.

**By hand, once per computer:**

- Installing VB-CABLE can make the cable's input ("CABLE Input", or
  "Speakers (VB-Audio Virtual Cable)" in newer versions) the Windows default speaker, so the computer goes silent and
  everything it plays reaches Zoom. Set the speaker back (taskbar speaker icon, e.g. "Speakers (Realtek
  Audio)"); OBS's monitoring stays on the cable.
- Zoom, Settings > Audio: **Microphone** "CABLE Output (VB-Audio Virtual Cable)"; **Speaker** the computer's
  speakers, never the cable's input; and **Original sound for musicians** turned on (in the meeting, the "Original
  sound" button must be on). With Zoom's background noise suppression instead, the organ, piano and held notes
  are removed as noise and the music barely comes through. If the option is missing, the Zoom account's web
  settings (zoom.us > Settings > Audio) must allow it. Camera: "OBS Virtual Camera".

Options: `-Branch` (default: the repo's default branch), `-RepoUrl`, `-RepoDir`. Not covered on Windows: the GNOME
dock, the PipeWire hum filter and the Ubuntu autoinstall. Testing it, and preparing a laptop to test on:
[docs/windows-testing.md](windows-testing.md).

## Automated Ubuntu install (autoinstall)

`autoinstall/` holds a template for installing Ubuntu on a new computer: Mountain time
(`America/Denver`), Wi-Fi, NVIDIA drivers, Chrome, Zoom, GNOME defaults, auto-login, and a
first-boot service that runs `setup-obs-flatpak.sh`.

```bash
cd autoinstall
cp secrets.env.example secrets.env   # fill in the hostname prefix, the broadcast password, the two Wi-Fi networks, wallpaper
./render-autoinstall.py              # writes user-data (git-ignored; it contains the secrets)
```

The installer creates one account, `broadcast` (auto-login, with sudo), and joins the two Wi-Fi networks
(`Liahona` and `Lehi`). The passwords are plain text in `secrets.env`; the account password is hashed (SHA-512)
when `user-data` is rendered. The first-boot service clones this repo to `/opt/church-obs-setup` and runs the
setup from there once.

Never commit `secrets.env` or `user-data`.

## Hum and tone filters (notches on the microphone)

OBS has no notch filter, so this repo has small VST 2.x plugins (`tools/hum-notch-vst/`). On Ubuntu the setup
script builds them into `~/.vst` with `build.sh` (needs `gcc`, which the setup script installs). On Windows they
are prebuilt as DLLs in `tools/hum-notch-vst/windows/` (by `build-windows.ps1`, with clang; rebuild and commit them
after changing the C files), and the setup copies them to `C:\Program Files\VSTPlugins`. Each filter has an eye
icon in OBS to turn it on and off without a blip. They are fixed notches, not adaptive, so they leave music alone
apart from a thin slice at each frequency:

| Filter | Removes |
|---|---|
| HumNotch | 60, 120, 180 and 240 Hz mains hum (Q 30) |
| SquealNotch | a steady, drifting whine near 10 kHz (Q 4, about 2.5 kHz wide) |
| Notch6381, Notch13623 | two steady tones at 6381 and 13623 Hz (Q 12), built from `tone_notch_vst.c` |

The tones were measured on the Independence Building microphone (Sound Blaster); check yours with a quiet-room
recording before keeping a notch. Every collection except the Control one has all four filters on "USB Audio",
and starts "USB Audio" at -8 dB.

- **Don't pick the plug-in from OBS's Filters dialog.** In the OBS Flatpak its plug-in list is empty and OBS saves a
  blank plug-in path. The collections store the path directly (`@HOME@/.vst/NAME.so`, which the Windows scripts
  rewrite to the DLL in `C:\Program Files\VSTPlugins`), and the setup script sets `VST_PATH` for the Flatpak so
  the path survives. To add another notch, copy an existing filter's entry.
- **Don't use these together with the PipeWire filter below.**
- A notch only hides the hum; a ground loop is still best fixed at the source (try a USB isolator, or a
  ground-lift/isolation transformer on the audio line, and unplug the ethernet briefly to test).

### PipeWire hum filter (optional, off by default, Ubuntu only)

`audio/hum-notch.conf` is a PipeWire filter-chain with the same four hum notches on the USB microphone. Run the setup
script with `NOTCH=1` to install it and point OBS's "USB Audio" source at the virtual microphone `hum_notch` ("USB
Audio (hum filtered)"), and remove the HumNotch filter from "USB Audio" (that would filter twice). No restart needed
(safe during a stream): run `tools/install-hum-notch.sh [mic-name]` as the normal user to load it now.
