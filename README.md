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
sudo ./setup-obs-flatpak.sh
```

This installs OBS Studio, DistroAV (NDI) and the obs-ptz PTZ Controls extension system-wide,
lets OBS reach the local network, and installs the FFmpeg libraries that NDI needs to decode
HX2/HX3 cameras.

- The obs-ptz Flatpak bundle is in `vendor/` (built from <https://github.com/smitchell7/obs-ptz>,
  a fork of <https://github.com/glikely/obs-ptz>, GPL-2.0; the source is in that repo). To use a
  different build, run `sudo PTZ_BUNDLE=/path/to/file.flatpak ./setup-obs-flatpak.sh`.
- It asks whether to add OBS to the GNOME dock (only offered on machines set up with the church
  autoinstall). Answer up front with `--pin-dock` or `--no-pin-dock`.
- It asks which building's OBS configuration to install (the folders in `configs/`, currently
  `quail-config`), or take `--config=quail-config` / `--no-config` up front. Each configuration is
  an OBS scene collection with that building's camera, presets and sacrament scene. Choose it
  afterwards from OBS's Scene Collection menu. An existing file is saved as `*.bak` first.
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
cp secrets.env.example secrets.env   # fill in the hostname prefix, password hash, Wi-Fi, wallpaper
./render-autoinstall.py              # writes user-data (git-ignored; it contains the secrets)
```

Never commit `secrets.env` or `user-data`.
