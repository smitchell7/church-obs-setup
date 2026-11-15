# Church OBS Configuration

This is meant to hold key configuration files for broadcasting meetings.

These are the key objectives:

1. Be very usable
2. Provide all tooling that you might want for a 2-camera broadcast on zoom or youtube

## Hardware 

- 1 to 2 cameras are intended to be used

## Features

- Stream (publish) audio from the computer to other machines on the local network
- OBS configuration pre-packaged
    - Stream from NDI cameras
    - Scene for the administration of the sacrament
    - PTZ control with key scenes:
        - Speaker
        - Rostrum (where speakers are sitting)
        - Conductor
        - Congregation
    - Lower third for speaker names
    - Captioning + live translation English to Spanish and Spanish to English
- Stream (publish) audio + video to Zoom



## Install OBS (Flatpak) on a new computer

```bash
sudo ./setup-obs-flatpak.sh             # new computer or later: install what is missing, refresh the configuration
sudo ./setup-obs-flatpak.sh --install   # also update the software that is already installed
```

The script can be run again at any time. It first checks that OBS, DistroAV, obs-ptz, the NDI decoder
libraries and the system tools are installed and installs only what is missing (on an up-to-date computer it
installs nothing), then refreshes the configuration (scenes, audio, Zoom microphone); close OBS first. Your
previous scene file is saved as `*.bak` whenever it changes.

Options: `--install` (also update what is already installed), `--config=alkire-and-quail|independence-building`
(the scene collection OBS opens on; without it, it asks in a terminal) or `--no-config` (skip the scene collections), `--pin-dock` or `--no-pin-dock` (add OBS to the dock). Environment:
`TARGET_USER=name` (default: whoever ran sudo), `AUDIO_DEVICE=name` (force the OBS audio input),
`PTZ_BUNDLE=/path/file.flatpak` (a different obs-ptz build), `DSK_REPO=owner/name` (download Downstream Keyer
from a different GitHub repo's releases), `DSK_BUNDLE=/path/file.flatpak` (install Downstream Keyer from a local
file instead), `OBS_X11=1` or `OBS_X11=0` (run OBS through X11/XWayland, or never; without it that happens only when OBS opens on
the Independence Building collection, because opening an external projector there under Wayland crashed OBS).
To undo it: `flatpak override --user --reset com.obsproject.Studio`, then run the script again.

`--install` installs OBS Studio, DistroAV (NDI) and the obs-ptz PTZ Controls extension system-wide,
lets OBS reach the local network, and installs the FFmpeg libraries that NDI needs to decode
HX2/HX3 cameras.

- The obs-ptz Flatpak bundle is in `vendor/` (built from <https://github.com/smitchell7/obs-ptz>,
  a fork of <https://github.com/glikely/obs-ptz>, GPL-2.0; the source is in that repo). To use a
  different build, run `sudo PTZ_BUNDLE=/path/to/file.flatpak ./setup-obs-flatpak.sh`.
- Downstream Keyer is downloaded on each run from the newest release (pre-releases included) of
  <https://github.com/harmanmj/obs-downstream-keyer>, a fork of <https://github.com/exeldro/obs-downstream-keyer>
  (GPL-2.0), whose releases each attach `obs-downstream-keyer-<version>-flatpak-x86_64.flatpak`. It adds Load On
  Scene, which shows a keyer only on the program scenes you choose, and Go Live / Go to Preview controls that work
  with Studio Mode. A computer that has Flathub's Downstream Keyer, or an older release, is switched to the newest
  release on the next run; publishing a new release on the fork is all it takes to update. If the fork has no
  Flatpak published, Flathub's is used. If GitHub can't be reached, the installed copy is kept (or, if there is
  none, Flathub's is installed until the next run).
- On a first setup it sets OBS's video to a 1920x1080 canvas and output at 30 fps, with recording quality "Same as
  stream", and skips its Auto-Configuration Wizard (`tools/set-obs-video.py` sets the video again).
- It installs the OBS window layout in `configs/obs-layout.ini`, with the PTZ Controls dock in the bottom row.
  A layout that already has PTZ Controls docked is left alone, so changes made in OBS survive a re-run.
- It asks whether to add OBS to the GNOME dock (only offered on machines set up with the church
  autoinstall). Answer up front with `--pin-dock` or `--no-pin-dock`.
- It installs every scene collection in `configs/` (alkire-and-quail and independence-building), then asks which
  one OBS opens on by default (1 alkire-and-quail, 2 independence-building), or take `--config=alkire-and-quail` or
  `--config=independence-building` up front; `--no-config` skips them. Each is an OBS scene collection with the
  cameras, PTZ presets and the sacrament scene. An existing file is saved as `*.bak` first. Run without a
  terminal and without `--config`, it installs them and leaves OBS's default collection as it is.
  - `alkire-and-quail`: one NDI camera at 192.168.111.245. Scenes, in preset order, are named with their slot:
    Joystick, Pulpit - P0, Chorister - P1, Rostrum - P2, Full Room - P3, Piano - P4, Speaker Close-up - P5,
    Piano and Pulpit - P6, Organ - P7, Choir - P8, Sacrament. **Joystick** shows the camera without recalling a
    preset, so it stays where it is and you can steer it with the PTZ Controls dock. Below Sacrament are
    **Lower Thirds - Lyrics** and **Lower Thirds - Speakers**, FreeShow lower thirds over NDI (pick the FreeShow
    output on each "Freeshow Lower Thirds" source in OBS), shown over the program by the **Lyrics** and
    **Speaker Names** downstream keyers.
  - `independence-building` ("Independence Building - Hardware" in OBS): two cameras, House Left
    (PTZ at 192.168.111.246) and House Right (PTZ at 192.168.111.245), each with its own PTZ device. Every scene
    above except Sacrament comes as a Left and a Right version ("Left Pulpit - P0", ...), with **Joystick Left**
    and **Joystick Right** in place of Joystick. The camera video comes from USB video capture devices instead
    of NDI: House Left from a USB HDMI capture device, House Right from a Blackmagic ATEM Mini. Pick each
    source's Device in OBS after setup (see `configs/independence-building/README.md`). It also has the stake
    conference scenes: FreeShow lower thirds over NDI, a camera Video Overlay and a Blackmagic scene.
  - Video comes from the cameras (their own audio is not used). Audio comes from the "USB Audio" source, a
    USB input (the Sound Blaster where there is one), in every scene except Sacrament. The installer picks the
    Sound Blaster, else any USB input, else the system default (`AUDIO_DEVICE=name` forces one; at first boot
    there is no desktop session, so it usually falls back to default: set the device on the source in OBS).
    The Sacrament scene plays the sacrament music instead and has no microphone, so changing to it switches
    the Zoom audio from the USB input to the music, and changing back switches it again.
  - Zoom: OBS monitors its audio (the USB input and the sacrament music) into a virtual speaker that only OBS
    uses, "OBS Monitoring (not for Zoom)" (`audio/obs-to-zoom.conf`), and a virtual microphone, "OBS Mic (for
    Zoom)", carries it (`audio/obs-mic.conf`, a remap of the speaker's monitor). Never make that
    microphone the system default: OBS's "USB Audio" source (and anything else on "default") would then
    record OBS's own output and feed it back, which sounds like a tone or howl. Ubuntu already uses PipeWire, which speaks the PulseAudio protocol, so
    PulseAudio itself is not needed (the installer adds `pulseaudio-utils` for `pactl`). PipeWire only reads
    these files when it starts, so if the user is logged in the installer restarts PipeWire when they change
    (audio drops for a moment; not during a Zoom call); otherwise they apply after the next login.
    `tools/set-obs-monitor.py` points OBS's monitoring device at the speaker and opens OBS in studio mode
    (OBS remembers the mode on exit, so if someone turns it off it stays off until the installer runs again).
  - **Zoom settings, once per computer** (Zoom keeps these itself, so the installer cannot set them):
    Settings > Audio: **Microphone** "OBS Mic (for Zoom)", picked by name (not "Same as System"); **Speaker** the computer's
    speakers or headphones, never "OBS Monitoring (not for Zoom)", which would send the meeting back into the
    microphone; under Music and Professional Audio, tick **Show in-meeting option to enable "Original sound
    for musicians"**, then in a meeting click **Original sound for musicians: Off** at the top left to turn it
    on (recent Zoom versions remember it; check at the start of each meeting). Without it Zoom's noise
    suppression chops up the music. Menu names vary a little between Zoom versions. If the
    option is missing, the Zoom account's web settings (zoom.us > Settings > Audio) must allow it.
  - Both audio sources have monitoring set to "Monitor and Output". OBS 33 needs `monitoring_enabled: true` in
    the scene file as well as `monitoring_type: 2`; with only the type set, nothing is sent to Zoom. If Zoom
    hears nothing, check Edit > Advanced Audio Properties in OBS: "USB Audio" and "Sacrament Music" must say
    "Monitor and Output".
  - Zoom video: OBS's Virtual Camera needs the `v4l2loopback` kernel module. When it is not loaded, OBS loads
    it itself with `pkexec`, which asks for an admin password every time. The installer installs
    `v4l2loopback-dkms` and loads the module at boot with OBS's own options
    (`/etc/modprobe.d/obs-virtualcam.conf`, `/etc/modules-load.d/obs-virtualcam.conf`), so Start Virtual
    Camera needs no password. In Zoom pick the camera "OBS Virtual Camera".
  - Remote control: OBS's WebSocket server is switched on by default (port 4455, password required). The
    password is `OBS_WEBSOCKET_PASSWORD` in `secrets.env` for the autoinstall, or the same variable when
    running the script by hand; if neither is set, the script uses its built-in default. That default is
    in this public repo, so set your own for anything that matters. `tools/set-obs-websocket.py` does this.
  - Presets are stored in the cameras: save positions in these slots on each camera so the scenes can recall
    them: 0 Pulpit, 1 Chorister, 2 Rostrum, 3 Full Room, 4 Piano, 5 Speaker Close-up, 6 Piano and Pulpit, 7 Organ, 8 Choir.
- It makes the sacrament background picture (`tools/make-sacrament-graphic.py` downloads *The Good Shepherd*
  from churchofjesuschrist.org and crops it; the message is OBS text layers in the scene; use `--image` for a
  different picture) in `~/Documents/sacrament/`.
- It builds the sacrament music playlist: the hymns listed in `audio/sacrament-playlist.txt` (one page name per
  line, in play order) are downloaded as piano accompaniments from churchofjesuschrist.org and joined with ffmpeg
  into `~/Documents/sacrament/sacrament-playlist.mp3`, which the Sacrament scene loops. To change the playlist, edit
  the list and run the installer again; it downloads only what is new. The music is not stored in this repo.
- Without the HX libraries, HX cameras show black video with "NDI video decoder not found".

## Install OBS on a Windows computer

One run installs everything and configures it. From an elevated PowerShell (right-click, Run as
administrator), signed in as the person who will use OBS:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1   # asks: 1 alkire-and-quail, 2 independence-building
```

The script can be downloaded on its own and run from anywhere: it installs Git (via `winget`), clones this
repo to `C:\church-obs-setup` (or updates it there with `git pull`), and carries on from that checkout, so a
computer always runs the current version. Run it again at any time to update; close OBS first. It then:

- installs OBS Studio 33+ and the NDI Runtime (`winget`), and the latest DistroAV, Downstream Keyer
  and obs-ptz releases from GitHub (Downstream Keyer is the fork `harmanmj/obs-downstream-keyer`, which adds Load
  On Scene, pre-releases included; `exeldro/obs-downstream-keyer` when the fork has none published, or always with
  `-DskRepo exeldro/obs-downstream-keyer`) (obs-ptz is upstream `glikely/obs-ptz`, whose 1.0 betas use the same preset format as these configs;
  `-PtzInstaller C:\path\...-Installer.exe` uses another build);
- installs ffmpeg (`winget`, for the playlist) and **VB-Audio Virtual Cable**, the virtual microphone for Zoom.
  VB-CABLE is donationware with its own licence (<https://vb-audio.com/Services/licensing.htm>); its setup
  window opens: click "Install Driver" and accept. It needs a Windows restart: restart, then run the script
  again to finish;
- installs every scene collection in `configs\` (an existing file is saved as `*.bak`) and makes the chosen
  one the one OBS opens on (`-Config alkire-and-quail|independence-building`, else it asks 1 or 2; `-NoConfig`
  skips the collections). The "USB Audio" source becomes a Windows (WASAPI) input on the Sound Blaster, else a USB input,
  else (with a warning) another real input, never "NDI Webcam Audio", whose sound is poor; plug the USB
  input in before running it. `-AudioDevice "part of its name"` picks another;
- points OBS's audio monitoring at "CABLE Input (VB-Audio Virtual Cable)", so the USB input and the
  sacrament music go to Zoom: in Zoom pick the microphone **CABLE Output (VB-Audio Virtual Cable)**;
- on a first setup, sets OBS's video to a 1920x1080 canvas and output at 30 fps, with recording quality "Same
  as stream", and skips its Auto-Configuration Wizard (`tools\set-obs-video.ps1` sets the video again);
- opens OBS in studio mode (OBS remembers the mode on exit, so if someone turns it off it stays off until the
  script runs again);
- installs the OBS window layout in `configs\obs-layout.ini`, with the PTZ Controls dock in the bottom row. A
  layout that already has PTZ Controls docked is left alone, so changes made in OBS survive a re-run;
- adds a firewall rule for NDI, makes the sacrament graphic, and builds the sacrament playlist from
  `audio\sacrament-playlist.txt` (`tools\make-sacrament-playlist.ps1`) in `Documents\sacrament`.

**By hand, once per computer:**

- Installing VB-CABLE can make "CABLE Input" the Windows default speaker, so the computer goes silent and
  everything it plays reaches Zoom. Set the speaker back (taskbar speaker icon, e.g. "Speakers (Realtek
  Audio)"); OBS's monitoring stays on CABLE Input.
- Zoom, Settings > Audio: **Microphone** "CABLE Output (VB-Audio Virtual Cable)"; **Speaker** the
  computer's speakers, never "CABLE Input"; and **Original sound for musicians** turned on (in the meeting,
  the "Original sound" button must be on). With Zoom's background noise suppression instead, the organ,
  piano and held notes are removed as noise and the music barely comes through. If the option is missing,
  the Zoom account's web settings (zoom.us > Settings > Audio) must allow it. Camera: "OBS Virtual Camera".

Options: `-Branch` (default: the repo's default branch), `-RepoUrl`, `-RepoDir`. Not covered on Windows: the GNOME dock, the
OBS WebSocket password, and the Ubuntu autoinstall. Testing it, and preparing a laptop to test on:
[docs/windows-testing.md](docs/windows-testing.md).

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
when `user-data` is rendered.

Never commit `secrets.env` or `user-data`.

## Hum and tone filters (notches on the microphone)

OBS has no notch filter, so the setup script builds small VST 2.x plugins (`tools/hum-notch-vst/`, built into `~/.vst` by
`build.sh`; needs `gcc`) and the Independence Building - Hardware collection has them as filters on its "USB Audio"
source. Each filter has an eye icon in OBS to turn it on and off without a blip. They are fixed notches, not adaptive,
so they leave music alone apart from a thin slice at each frequency:

| Filter | Removes |
|---|---|
| HumNotch | 60, 120, 180 and 240 Hz mains hum (Q 30) |
| SquealNotch | a steady, drifting whine near 10 kHz (Q 4, about 2.5 kHz wide) |
| Notch6381, Notch13623 | two steady tones at 6381 and 13623 Hz (Q 12), built from `tone_notch_vst.c` |

The tones were measured on the Independence Building microphone (Sound Blaster); check yours with a quiet-room recording
before keeping a notch. Alkire and Quail only has HumNotch.

- **Don't pick the plug-in from OBS's Filters dialog.** In the OBS Flatpak its plug-in list is empty and OBS saves a blank
  plug-in path. The collections store the path directly, and the setup script sets `VST_PATH` for the Flatpak so the path
  survives. To add another notch, copy an existing filter's entry (`plugin_path` is the `.so` in `~/.vst`).
- **Don't use these together with the PipeWire filter below.**
- A notch only hides the hum; a ground loop is still best fixed at the source (try a USB isolator, or a
  ground-lift/isolation transformer on the audio line, and unplug the ethernet briefly to test).

### PipeWire hum filter (optional, off by default)

`audio/hum-notch.conf` is a PipeWire filter-chain with the same four hum notches on the USB microphone. Run the setup script with
`NOTCH=1` to install it and point OBS's "USB Audio" source at the virtual microphone `hum_notch` ("USB Audio (hum filtered)"),
and remove the HumNotch filter from "USB Audio" (that would filter twice). No restart needed (safe during a stream): run
`tools/install-hum-notch.sh [mic-name]` as the normal user to load it now.
