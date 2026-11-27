# Church OBS Configuration
Setup scripts and OBS configuration for broadcasting church meetings over Zoom or Youtube from OBS Studio, with one or two PTZ cameras. One run of a setup script turns a computer into a ready-to-use broadcast computer: OBS, the required OBS Plugins,the scene collections, the audio routing into Zoom and the window layout. An OBS Configuration update script puts the OBS configuration back to this repo's version whenever something was changed by accident.

**Ubuntu is the main platform used for running broadcasts.** The Windows scripts do the same job and are kept as a backup, for when a Windows laptop has to stand in on a broadcast.

## Where to find things

| Document | For |
|---|---|
| [Ubuntu Install README.md](Ubuntu%20Install%20README.md) | Step-by-step: installing and updating a computer running Ubuntu as its operating system |
| [Windows Install README.md](Windows%20Install%20README.md) |Step-by-step: installing and updating a computer running Windows as its operating system |
| [obs-configuration/README.md](obs-configuration/README.md) | The scene collections: which building and meeting each is for, the cameras and capture devices, the lower thirds, the control laptop, the OBS window layout |
| [docs/technical-reference.md](docs/technical-reference.md) | What the scripts do in detail, their options, the audio and Zoom routing, the notch filters and the autoinstall: for people maintaining the scripts |
| [docs/ethernet-hardware-id-configuration.md](docs/ethernet-hardware-id-configuration.md) | Giving an Ubuntu OBS computer the same IP address every time: a fixed MAC on its wired connection and a router reservation |

## Features

- **Scene collections for each building and meeting:** sacrament meetings and stake broadcasts, in both buildings
  (see [Scene collections](#scene-collections)).
- **PTZ camera presets as scenes:** Pulpit - P0, Chorister - P1, Rostrum - P2, Full Room - P3, Piano - P4,
  Speaker Close-up - P5, Piano and Pulpit - P6, Organ - P7 and Choir - P8 move the camera to that preset. Camera
  scenes (Stake Meeting) leave it where it is, to steer with the PTZ Controls dock.
- **Sacrament scene:** a background picture with title text, and a looping playlist of hymn accompaniments,
  with the microphone off.
- **Stake Meeting extras:** FreeShow lower thirds (lyrics and speaker names) over NDI, a camera picture-in-picture,
  shown with Downstream Keyer; in Independence, a Blackmagic scene for the ATEM Mini's other inputs.
- **Control laptop:** a second computer shows both cameras from the main OBS (with LIVE and PREVIEW outlines)
  and steers them, over OBS's WebSocket.
- **Zoom:** OBS's audio goes to a virtual microphone and its picture to OBS's Virtual Camera.
- **Clean microphone:** four notch filters (mains hum, a high whine and two steady tones) on the USB microphone.
- **Ready to use:** Studio Mode, a set window layout with the PTZ Controls dock, a multiview per collection, and
  1920x1080 video at 30 fps.
- **Repairable:** the update script puts the scenes, layout and OBS settings back to this repo's predefined settings, without requiring an admin password.

## Scene collections

The setup installs all five collections. The setup asks which one OBS opens on, and any of them can be opened
later from OBS's **Scene Collection** menu.

| Collection (name in OBS) | Building | For |
|---|---|---|
| Sacrament - Alkire and Quail Building | Alkire and Quail: one PTZ camera, video over NDI | Weekly sacrament meetings: the P0 to P8 preset scenes and Sacrament |
| Sacrament - Independence Building | Independence: two PTZ cameras, video over USB capture devices from the video rack | Weekly sacrament meetings: Left and Right P0 to P8 and Sacrament |
| Stake Meeting - Alkire and Quail Building | Alkire and Quail | Stake broadcasts, run on its own: adds a Camera scene and the lower thirds |
| Stake Meeting - Independence Building | Independence | Stake broadcasts, as the main OBS: Left and Right Camera, Pulpit and Full Room, Sacrament, Blackmagic and the lower thirds Control Laptop highly recomended (see next scene collection) |
| Stake Meeting - Independence Building - Control | Independence | A second laptop at stake broadcasts: shows both cameras from the main OBS and steers them |

For information on what each scene collection has, how to pick the capture devices, and how to set up the control laptop:
[obs-configuration/README.md](obs-configuration/README.md).

## Installation

First-time installation on a new computer. If OBS is already installed, make sure it is closed before running the script. For updating a computer that is already set up, see the install guides.

**Ubuntu** ([install guide](Ubuntu%20Install%20README.md)): in a terminal, then type the number of the scene collection OBS should open on when it asks:

```bash
cd ~
git clone https://github.com/smitchell7/church-obs-setup.git
cd ~/church-obs-setup
sudo ./setup-obs-flatpak.sh
```

**Windows** ([install guide](Windows%20Install%20README.md)): in PowerShell as administrator, then type the number of the scene collection OBS should open on when it asks:

```powershell
cd $env:TEMP
irm https://raw.githubusercontent.com/smitchell7/church-obs-setup/HEAD/setup-obs-windows.ps1 -OutFile setup-obs-windows.ps1
powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1
```

## Resetting the OBS configuration to the defaults

If something in OBS was changed by accident (a scene or collection deleted, a dock closed or moved, Studio Mode
turned off, Zoom hearing nothing), the configuration update script puts it all back to this repo's version. It
keeps the cameras, microphone and NDI sources picked in OBS, and asks which scene collection OBS should open
on (press Enter to keep the current one). It installs no
software and needs no admin password. Close OBS first.

**Ubuntu**: press the **OBS Configuration Reset** button in the dock (next to OBS). Or, in a normal terminal (no sudo):

```bash
cd ~/church-obs-setup
git checkout main
git pull
python3 tools/obs-config-update.py
```

**Windows**, in a normal PowerShell:

```powershell
cd c:\church-obs-setup
git checkout main
git pull
powershell -ExecutionPolicy Bypass -File .\tools\obs-config-update.ps1
```

What it resets and what it keeps, in detail: [technical reference](docs/technical-reference.md#keeping-computers-up-to-date-obs-config-update).

## What's in this repo

| Path | What it is |
|---|---|
| `setup-obs-flatpak.sh` | The Ubuntu setup script (run with sudo) |
| `setup-obs-windows.ps1` | The Windows setup script (backup) |
| `obs-configuration/` | The scene collections, one folder each, and the OBS window layout ([guide](obs-configuration/README.md)) |
| `tools/` | The update script (`obs-config-update`) and the smaller tools the setup scripts use, each as a `.py` (Ubuntu) and `.ps1` (Windows) pair |
| `tools/hum-notch-vst/` | The notch filter plugins: C source, the Linux build script, and prebuilt Windows DLLs |
| `audio/` | PipeWire files for the Zoom microphone, and the sacrament playlist |
| `autoinstall/` | A template for installing Ubuntu on a new computer, unattended |
| `vendor/` | The obs-ptz Flatpak bundle |
| `docs/` | The technical reference, the Ethernet hardware ID guide and the Windows test guide |

For how the scripts work, their options and how to change them, see the
[technical reference](docs/technical-reference.md).
