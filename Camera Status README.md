# Camera Status

Checks whether each PTZ camera is powered **ON** or in **STANDBY**. Use it to confirm the cameras turned
on when OBS opened, or turned off when OBS closed. With the toggle option it can also switch them: a camera
in standby is turned on, and a camera that is on is put in standby.

There are two versions of the same script, both in the `tools/camera-status` folder of `church-obs-setup`:

- `tools/camera-status/camera-status.py` for Ubuntu (Linux)
- `tools/camera-status/camera-status.ps1` for Windows

The scripts work on their own: they don't use OBS or its scene collections, and OBS does not need to be
installed or open. They talk to the cameras directly over the network.

## Camera addresses

The camera addresses are in `tools/camera-status/cameras.json`, which both scripts read:

    {
        "single": [
            { "name": "PTZ Device", "host": "192.168.111.245", "port": 5678 }
        ],
        "dual": [
            { "name": "PTZ Left", "host": "192.168.111.245", "port": 5678 },
            { "name": "PTZ Right", "host": "192.168.111.246", "port": 5678 }
        ]
    }

- `single` is the camera for a single-camera setup, and `dual` is the two cameras for a dual-camera setup.
- `name` is only the label the script prints.
- `host` is the camera's IP address, and `port` is its VISCA TCP port (5678 unless it was changed on the
  camera).

If a camera's address changes, edit this file. The address set for the camera in OBS is not updated by this
file, and OBS's address is not read by the scripts, so change both when a camera moves.

To ask one camera without editing the file, give its address with `--host` (Windows: `-CameraHost`). See
**Options** below.

## Install

The scripts come with `church-obs-setup`, so updating the existing folder installs them. Nothing else is
needed: Ubuntu already has Python 3, and Windows already has PowerShell.

Ubuntu:

    cd ~/church-obs-setup
    sudo git pull

Windows (PowerShell):

    cd C:\church-obs-setup
    git pull

## Run

Ubuntu, single camera:

    cd ~/church-obs-setup
    python3 tools/camera-status/camera-status.py single

Ubuntu, dual camera:

    cd ~/church-obs-setup
    python3 tools/camera-status/camera-status.py dual

Windows, single camera:

    cd C:\church-obs-setup
    powershell -ExecutionPolicy Bypass -File .\tools\camera-status\camera-status.ps1 single

Windows, dual camera:

    cd C:\church-obs-setup
    powershell -ExecutionPolicy Bypass -File .\tools\camera-status\camera-status.ps1 dual

## Turn cameras on or off (toggle)

Add `--toggle` (Ubuntu) or `-Toggle` (Windows) to switch each camera's power:

- a camera in **STANDBY** is turned **on**
- a camera that is **ON** is put in **standby**

Each camera is switched on its own, so if one is on and the other is in standby, they swap.

Ubuntu, single camera:

    cd ~/church-obs-setup
    python3 tools/camera-status/camera-status.py single --toggle

Ubuntu, dual camera:

    cd ~/church-obs-setup
    python3 tools/camera-status/camera-status.py dual --toggle

Windows, single camera:

    cd C:\church-obs-setup
    powershell -ExecutionPolicy Bypass -File .\tools\camera-status\camera-status.ps1 single -Toggle

Windows, dual camera:

    cd C:\church-obs-setup
    powershell -ExecutionPolicy Bypass -File .\tools\camera-status\camera-status.ps1 dual -Toggle

The result shows the power state each camera had **before** the toggle, and what was done:

    Cameras from C:\church-obs-setup\tools\camera-status\cameras.json
      PTZ Left (192.168.111.245:5678): STANDBY, turned on
      PTZ Right (192.168.111.246:5678): ON, put in standby

- **still finishing** after the action means the camera accepted the command but was still powering up or
  down when the script stopped waiting. That is normal, since a camera can take several seconds to turn on.
  Run the script again without the toggle option to see the new state.
- A camera that shows **NO ANSWER** or **POWER ERROR** is left alone.

Without the toggle option the script only reports and changes nothing.

## What it shows

    Cameras from /home/broadcast/church-obs-setup/tools/camera-status/cameras.json
      PTZ Left (192.168.111.245:5678): ON
      PTZ Right (192.168.111.246:5678): STANDBY

- **ON**: the camera is powered on.
- **STANDBY**: the camera is powered off (in standby) but still on the network.
- **NO ANSWER**: the camera could not be reached. Check that it is plugged in, connected to the network, and
  at the address shown.

## Options

- `--toggle` (Windows: `-Toggle`) turns on each camera in standby and puts each camera that is on in
  standby. See **Turn cameras on or off (toggle)** above.
- `--host ADDRESS` (Windows: `-CameraHost ADDRESS`) asks this camera instead of the ones in
  `cameras.json`, and `single` or `dual` is then not needed. Add `:PORT` if the port is not 5678. To ask
  more than one, repeat `--host` on Ubuntu, or separate the addresses with commas on Windows:

      python3 tools/camera-status/camera-status.py --host 192.168.111.245 --host 192.168.111.246
      powershell -ExecutionPolicy Bypass -File .\tools\camera-status\camera-status.ps1 -CameraHost 192.168.111.245,192.168.111.246

- `--cameras FILE` (Windows: `-Cameras FILE`) reads the camera addresses from a different file laid out like
  `cameras.json`.
- `--timeout SECONDS` (Windows: `-Timeout SECONDS`) waits longer for each camera. The default is 3 seconds.

The script exits with status 0 when every camera answered, 1 when any did not, and 2 when it wasn't told
which cameras to ask.
