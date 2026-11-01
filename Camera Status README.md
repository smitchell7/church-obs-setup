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

The camera addresses are in `tools/camera-status/cameras.json`, which both scripts read. It lists:

| name      | host            | port |
|-----------|-----------------|------|
| PTZ Left  | 192.168.111.245 | 5678 |
| PTZ Right | 192.168.111.246 | 5678 |

- `name` is the label the script prints for the camera.
- `host` is the camera's IP address, and `port` is its VISCA TCP port (5678 unless it was changed on the
  camera).
- The first camera (192.168.111.245) is also the camera of a single-camera church.

If a camera's address changes, edit this file. The address set for the camera in OBS is not updated by this
file, and OBS's address is not read by the scripts, so change both when a camera moves.

To ask one camera without editing the file, give its address with `--host` (Windows: `-CameraHost`). See
**Options** below.

## Script Installation

The scripts come with `church-obs-setup`, so updating the existing folder installs them. Nothing else is
needed: Ubuntu already has Python 3, and Windows already has PowerShell.

Ubuntu:

```bash
cd ~/church-obs-setup
sudo git pull
```

Windows (PowerShell):

```powershell
cd C:\church-obs-setup
git pull
```

## Run Status Script

Ubuntu:

```bash
cd ~/church-obs-setup
python3 tools/camera-status/camera-status.py
```

Windows:

```powershell
cd C:\church-obs-setup
powershell -ExecutionPolicy Bypass -File .\tools\camera-status\camera-status.ps1
```

## Use Menu to update camera status

The script asks both cameras in `cameras.json`, then shows what it found:

- **Both cameras answer** (Expected result in the Independence Building): they are shown as **PTZ Left** and **PTZ Right**.

  `PTZ Left (192.168.111.245:5678): ON`\
  `PTZ Right (192.168.111.246:5678): STANDBY`

- **Only 192.168.111.245 answers** (Expected Result in Alkire and Quail Buildings): it is shown as **PTZ Camera**, and the second camera is not mentioned. 
    
    If you are in the independence building and this is the result you receive, check that PTZ Right is Plugged in, connected to the network and at its address (192.168.111.246)

  `PTZ Camera (192.168.111.245:5678): ON`

- **Only 192.168.111.246 answers**: it is shown as **PTZ Right**, with an error that the left camera is
  missing

  `PTZ Right (192.168.111.246:5678): ON`\
  `Error: PTZ Left not found. Check that PTZ Left is plugged in, connected to the network and at its address (192.168.111.245)`

- **No camera answers**: each is shown as **NO ANSWER**, with the reason, followed by an error that says
  what to check and what IP address each camera should be at. The script ends without the menu.

  `PTZ Left (192.168.111.245:5678): NO ANSWER (timed out connecting)`\
  `PTZ Right (192.168.111.246:5678): NO ANSWER (timed out connecting)`\
  `Error: PTZ cameras not found. Check that this computer is connected to the church network, check that all PTZ cameras are plugged in, connected to the network and at the correct addresses. For a one camera building the address is (192.168.111.245) and for two camera buildings the addresses are (192.168.111.245) for the left camera and (192.168.111.246) for the right camera`

## What the reported states mean

- **ON**: the camera is powered on.
- **STANDBY**: the camera is powered off (in standby) but still on the network.
- **NO ANSWER**: the camera could not be reached. Check that it is plugged in, connected to the network, and
  at the address shown.

## Status Options Menu

After it shows each camera's power state, the script asks what to do:
This will change the state for all cameras reported by the script to the selected status

`PTZ Left (192.168.111.245:5678): ON`\
`PTZ Right (192.168.111.246:5678): STANDBY`

`1. No change`\
`2. Set on`\
`3. Set standby`\
`Choose 1-3:`

Type a number and press Enter:

- **1. No change**: leaves every camera as it is, and the script ends.
- **2. Set on**: turns **every** camera that was found on, whatever state each one is in.
- **3. Set standby**: puts **every** camera that was found in standby, whatever state each one is in.


if option 2 or 3 are selected, the script returns the power state each camera had **before**, and what was done. A camera
that was already in that state still gets the command, and shows **(it already was)**:

`PTZ Left (192.168.111.245:5678): ON, turned on (it already was)`\
`PTZ Right (192.168.111.246:5678): STANDBY, turned on`

**still finishing** after the action means the camera accepted the command but was still powering up or
down when the script stopped waiting. That is normal, since a camera can take several seconds to turn on.
Run the script again to see the new state.

## Directly Set Camera Status Without Menu

To turn the cameras on or put them in standby without the menu, add
`--set on` or `--set standby` (Ubuntu), or `-Set On` or `-Set Standby` (Windows). It does the same as
choosing 2 or 3 in the menu.

Ubuntu, all cameras on:

```bash
cd ~/church-obs-setup
python3 tools/camera-status/camera-status.py --set on
```

Ubuntu, all cameras in standby:

```bash
cd ~/church-obs-setup
python3 tools/camera-status/camera-status.py --set standby
```

Windows, all cameras on:

```powershell
cd C:\church-obs-setup
powershell -ExecutionPolicy Bypass -File .\tools\camera-status\camera-status.ps1 -Set On
```

Windows, all cameras in standby:

```powershell
cd C:\church-obs-setup
powershell -ExecutionPolicy Bypass -File .\tools\camera-status\camera-status.ps1 -Set Standby
```

The result looks like the one after choosing 2 or 3 in the menu.



## Options

- `--set on` / `--set standby` (Windows: `-Set On` / `-Set Standby`) turns every camera that was found on,
  or puts it in standby, without the menu. See **Skip the menu (set)** above.
- `--host ADDRESS` (Windows: `-CameraHost ADDRESS`) asks this camera instead of the ones in
  `cameras.json`. Add `:PORT` if the port is not 5678. To ask more than one, repeat `--host` on Ubuntu, or
  separate the addresses with commas on Windows:

  ```bash
  python3 tools/camera-status/camera-status.py --host 192.168.111.245 --host 192.168.111.246
  ```

  ```powershell
  powershell -ExecutionPolicy Bypass -File .\tools\camera-status\camera-status.ps1 -CameraHost 192.168.111.245,192.168.111.246
  ```

- `--cameras FILE` (Windows: `-Cameras FILE`) reads the camera addresses from a different file laid out like
  `cameras.json`.
- `--timeout SECONDS` (Windows: `-Timeout SECONDS`) waits longer for each camera. The default is 3 seconds.

The script exits with status 0 when every camera answered (or, at a single-camera church, its one camera
did), and 1 when a camera was not found or no camera answered.
