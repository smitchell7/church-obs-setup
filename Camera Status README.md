# Camera Status

Checks whether each PTZ camera is powered **ON** or in **STANDBY**. Use it to confirm the cameras turned
on when OBS opened, or turned off when OBS closed. After showing each camera's state, it offers a menu to
leave the cameras as they are, turn them all on, or put them all in standby.

There are two versions of the same script, both in the `tools/camera-status` folder of `church-obs-setup`:

- `tools/camera-status/camera-status.py` for Ubuntu (Linux)
- `tools/camera-status/camera-status.ps1` for Windows

The scripts work on their own: they don't use OBS or its scene collections, and OBS does not need to be
installed or open. They talk to the cameras directly over the network.

The same command works for single-camera and dual-camera churches. The script finds out which cameras are
there (see **One camera or two** below).

## Camera addresses

The camera addresses are in `tools/camera-status/cameras.json`, which both scripts read:

    [
        { "name": "PTZ Left", "host": "192.168.111.245", "port": 5678 },
        { "name": "PTZ Right", "host": "192.168.111.246", "port": 5678 }
    ]

- `name` is the label the script prints for the camera.
- `host` is the camera's IP address, and `port` is its VISCA TCP port (5678 unless it was changed on the
  camera).
- The first camera (192.168.111.245) is also the camera of a single-camera church.

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

Ubuntu:

    cd ~/church-obs-setup
    python3 tools/camera-status/camera-status.py

Windows:

    cd C:\church-obs-setup
    powershell -ExecutionPolicy Bypass -File .\tools\camera-status\camera-status.ps1

## One camera or two

The script asks both cameras in `cameras.json`, then shows what it found:

- **Both cameras answer** (a dual-camera church): they are shown as **PTZ Left** and **PTZ Right**.

      PTZ Left (192.168.111.245:5678): ON
      PTZ Right (192.168.111.246:5678): STANDBY

- **Only 192.168.111.245 answers** (a single-camera church): it is shown as **PTZ Camera**, and the second
  camera is not mentioned.

      PTZ Camera (192.168.111.245:5678): ON

- **Only 192.168.111.246 answers**: it is shown as **PTZ Right**, with an error that the left camera is
  missing and what to check.

      PTZ Right (192.168.111.246:5678): ON
      Error: PTZ Left not found. Check that PTZ Left is plugged in, connected to the network and at its address (192.168.111.245)

- **No camera answers**: each is shown as **NO ANSWER**, with the reason, and the script ends without the
  menu.

      PTZ Left (192.168.111.245:5678): NO ANSWER (timed out connecting)
      PTZ Right (192.168.111.246:5678): NO ANSWER (timed out connecting)

At a dual-camera church where PTZ Right is off the network, only PTZ Left answers, so it is shown as
**PTZ Camera**. If a dual-camera church sees **PTZ Camera**, check PTZ Right.

## The menu

After it shows each camera's power state, the script asks what to do:

      PTZ Left (192.168.111.245:5678): ON
      PTZ Right (192.168.111.246:5678): STANDBY

      1. No change
      2. Set on
      3. Set standby
    Choose 1-3:

Type a number and press Enter:

- **1. No change**: leaves every camera as it is, and the script ends.
- **2. Set on**: turns **every** camera that was found on, whatever state each one is in.
- **3. Set standby**: puts **every** camera that was found in standby, whatever state each one is in.

For dual cameras, 2 or 3 gets both cameras to the same state. Any other answer asks again. A camera that was
not found (such as **Error: PTZ Left not found**) is not changed.

After 2 or 3, the script shows the power state each camera had **before**, and what was done. A camera
that was already in that state still gets the command, and shows **(it already was)**:

      PTZ Left (192.168.111.245:5678): ON, turned on (it already was)
      PTZ Right (192.168.111.246:5678): STANDBY, turned on

**still finishing** after the action means the camera accepted the command but was still powering up or
down when the script stopped waiting. That is normal, since a camera can take several seconds to turn on.
Run the script again to see the new state.

## Skip the menu (set)

To turn the cameras on or put them in standby without the menu, for example from a desktop shortcut, add
`--set on` or `--set standby` (Ubuntu), or `-Set On` or `-Set Standby` (Windows). It does the same as
choosing 2 or 3 in the menu.

Ubuntu, all cameras on, or all in standby:

    cd ~/church-obs-setup
    python3 tools/camera-status/camera-status.py --set on
    python3 tools/camera-status/camera-status.py --set standby

Windows, all cameras on, or all in standby:

    cd C:\church-obs-setup
    powershell -ExecutionPolicy Bypass -File .\tools\camera-status\camera-status.ps1 -Set On
    powershell -ExecutionPolicy Bypass -File .\tools\camera-status\camera-status.ps1 -Set Standby

The result looks like the one after choosing 2 or 3 in the menu.

## What the states mean

- **ON**: the camera is powered on.
- **STANDBY**: the camera is powered off (in standby) but still on the network.
- **NO ANSWER**: the camera could not be reached. Check that it is plugged in, connected to the network, and
  at the address shown.
- **Error: PTZ Left not found**: the other camera answered but this one did not. The message says what to
  check, and the address the script tried.

## Options

- `--set on` / `--set standby` (Windows: `-Set On` / `-Set Standby`) turns every camera that was found on,
  or puts it in standby, without the menu. See **Skip the menu (set)** above.
- `--host ADDRESS` (Windows: `-CameraHost ADDRESS`) asks this camera instead of the ones in
  `cameras.json`. Add `:PORT` if the port is not 5678. To ask more than one, repeat `--host` on Ubuntu, or
  separate the addresses with commas on Windows:

      python3 tools/camera-status/camera-status.py --host 192.168.111.245 --host 192.168.111.246
      powershell -ExecutionPolicy Bypass -File .\tools\camera-status\camera-status.ps1 -CameraHost 192.168.111.245,192.168.111.246

- `--cameras FILE` (Windows: `-Cameras FILE`) reads the camera addresses from a different file laid out like
  `cameras.json`.
- `--timeout SECONDS` (Windows: `-Timeout SECONDS`) waits longer for each camera. The default is 3 seconds.

The script exits with status 0 when every camera answered (or, at a single-camera church, its one camera
did), and 1 when a camera was not found or no camera answered.
