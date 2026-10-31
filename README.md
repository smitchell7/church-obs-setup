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
sudo ./setup-obs-flatpak.sh --config=dual-camera             # new computer or later: install what is missing, refresh the configuration
sudo ./setup-obs-flatpak.sh --install --config=dual-camera   # also update the software that is already installed
```

The script can be run again at any time. It first checks that OBS, DistroAV, obs-ptz, the NDI decoder
libraries and the system tools are installed and installs only what is missing (on an up-to-date computer it
installs nothing), then refreshes the configuration (scenes, audio, Zoom microphone); close OBS first. Your
previous scene file is saved as `*.bak` whenever it changes.

Options: `--install` (also update what is already installed), `--config=single-camera|dual-camera` or `--no-config`
(without either it asks in a terminal), `--pin-dock` or `--no-pin-dock` (add OBS to the dock). Environment:
`TARGET_USER=name` (default: whoever ran sudo), `AUDIO_DEVICE=name` (force the OBS audio input),
`PTZ_BUNDLE=/path/file.flatpak` (a different obs-ptz build).

`--install` installs OBS Studio, DistroAV (NDI) and the obs-ptz PTZ Controls extension system-wide,
lets OBS reach the local network, and installs the FFmpeg libraries that NDI needs to decode
HX2/HX3 cameras.

- The obs-ptz Flatpak bundle is in `vendor/` (built from <https://github.com/smitchell7/obs-ptz>,
  a fork of <https://github.com/glikely/obs-ptz>, GPL-2.0; the source is in that repo). To use a
  different build, run `sudo PTZ_BUNDLE=/path/to/file.flatpak ./setup-obs-flatpak.sh`.
- It asks whether to add OBS to the GNOME dock (only offered on machines set up with the church
  autoinstall). Answer up front with `--pin-dock` or `--no-pin-dock`.
- It asks which camera setup to install (the folders in `configs/`), or take `--config=single-camera`,
  `--config=dual-camera` or `--no-config` up front. Each is an OBS scene collection with the cameras, PTZ
  presets and the sacrament scene. Choose it afterwards from OBS's Scene Collection menu. An existing file is
  saved as `*.bak` first.
  - `single-camera`: one NDI camera at 192.168.111.245. Scenes: Pulpit, Rostrum, Full Room, Chorister, Piano,
    Speaker Close-up, Organ, Choir, Sacrament.
  - `dual-camera`: adds a second camera at 192.168.111.246 (245 is "Left", 246 is "Right"), each with its own
    PTZ device. Every scene above except Sacrament comes as a Left and a Right version ("Left Pulpit", ...).
  - Video comes from the cameras (their own NDI audio is not used). Audio comes from the "USB Audio" source, a
    USB input (the Sound Blaster where there is one), in every scene except Sacrament. The installer picks the
    Sound Blaster, else any USB input, else the system default (`AUDIO_DEVICE=name` forces one; at first boot
    there is no desktop session, so it usually falls back to default: set the device on the source in OBS).
    The Sacrament scene plays the music track and has no microphone.
  - Zoom: OBS monitors its audio (the USB input and the sacrament music) into a virtual device, "OBS to Zoom",
    and a virtual microphone "OBS Mic (for Zoom)" carries it. In Zoom pick that microphone. Ubuntu already
    uses PipeWire, which speaks the PulseAudio protocol, so PulseAudio itself is not needed (the installer
    adds `pulseaudio-utils` for `pactl`). The virtual devices appear after the next login or reboot
    (`audio/obs-to-zoom.conf`); `tools/set-obs-monitor.py` points OBS's monitoring device at them.
  - Remote control: OBS's WebSocket server is switched on by default (port 4455, password required). The
    password is `OBS_WEBSOCKET_PASSWORD` in `secrets.env` for the autoinstall, or the same variable when
    running the script by hand; if neither is set, the script uses its built-in default. That default is
    in this public repo, so set your own for anything that matters. `tools/set-obs-websocket.py` does this.
  - Presets are stored in the cameras: save positions in these slots on each camera so the scenes can recall
    them: 0 Pulpit, 1 Chorister, 2 Rostrum, 3 Full Room, 4 Piano, 5 Speaker Close-up, 6 Organ, 7 Choir.
- It makes the sacrament background picture (`tools/make-sacrament-graphic.py` downloads *The Good Shepherd*
  from churchofjesuschrist.org and crops it; the message is OBS text layers in the scene; use `--image` for a
  different picture) in `~/Documents/sacrament/` and downloads the sacrament music (piano accompaniment of "Bread of Life, Living Water" from
  churchofjesuschrist.org) to `~/Documents/sacrament/`. The music is not stored in this repo.
- Without the HX libraries, HX cameras show black video with "NDI video decoder not found".

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
