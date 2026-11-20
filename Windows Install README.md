# Windows Script Instructions

# Scene Collection information
  The setup script installs every scene collection and asks which one OBS should open on. On a computer that is already set up, the one OBS was using is marked (current) and pressing Enter keeps it:
    1) sacrament-alkire-and-quail (Sacrament - Alkire and Quail Building)
    2) sacrament-independence (Sacrament - Independence Building)
    3) stake-meeting-alkire-and-quail (Stake Meeting - Alkire and Quail Building)
    4) stake-meeting-independence (Stake Meeting - Independence Building)
    5) stake-meeting-independence-control (Stake Meeting - Independence Building - Control)
  Any of them can be opened later from OBS's Scene Collection menu.

  What is in each collection, which building and meeting it is for, and how to set up the cameras and the control laptop are all in the **[OBS Configuration guide](obs-configuration/README.md)**.

  **Independence Building:** after setup, plug in both video capture devices, open OBS and pick the Device on the "House Left - USB3.0 Video" and "House Right - ATEM Mini" sources in each Independence collection (see the guide).

# Downstream Keyer
  `setup-obs-windows.ps1` installs Downstream Keyer from the installer attached to the newest release of a fork on GitHub (https://github.com/harmanmj/obs-downstream-keyer). The fork adds the Load On Scene option (a keyer can be set to show only on the program scenes you choose) and Go Live / Go to Preview controls that work with Studio Mode.
  Each time the setup script runs, it installs the newest release over the one already there. If the fork has no Windows installer published, or GitHub or the fork can't be reached, it installs exeldro's release (https://github.com/exeldro/obs-downstream-keyer) instead.

# First Time Windows Install
  1. Open **PowerShell as administrator** (Start, type `powershell`, right-click > Run as administrator)
  2. Run the following, then type the number of the scene collection OBS should open on when it asks
    ```powershell
    cd $env:TEMP
    irm https://raw.githubusercontent.com/smitchell7/church-obs-setup/HEAD/setup-obs-windows.ps1 -OutFile setup-obs-windows.ps1
    powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1
    ```

# Running Updates on an existing installation
* **Update** (asks which scene collection OBS should open on; press Enter to keep the current one). The setup script gets the latest version itself: it switches `c:\church-obs-setup` to `main` and pulls before it runs, so there is no `git pull` step here.
    ```powershell
    cd c:\church-obs-setup
    powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1
    ```

# Updating Only the Scene Collections and OBS Configuration
Use this when only the scene collections have changed. It installs the newest version of every scene collection in `obs-configuration\` without running the rest of the setup (no software is installed). The devices already picked in OBS (the cameras, the USB Audio microphone and the FreeShow NDI sources) are kept, and each collection it replaces is saved as a `.bak` file. It also installs the notch filter plugins used on USB Audio if they are missing or out of date; that needs administrator, so in a normal PowerShell it prints the command to run in an administrator PowerShell instead (the full setup above installs them itself). It points OBS's audio monitoring at the virtual cable that Zoom listens to, and turns on OBS's WebSocket server for remote control (keeping its password). The video settings are left as they are. It puts back the OBS window layout (`obs-configuration\obs-layout.ini`), so docks closed or moved by accident come back. It turns Studio Mode on. Close OBS, then run the following in a normal PowerShell (not as administrator):
* **Update the Scene Collections** (asks which scene collection OBS should open on; press Enter to keep the current one)
    ```powershell
    cd c:\church-obs-setup
    git checkout main
    git pull
    powershell -ExecutionPolicy Bypass -File .\tools\obs-config-update.ps1
    ```

# Resetting OBS Video Settings
The video settings (1920x1080 canvas and output, 30 fps, recording quality "Same as stream") are only set the first time the script sets up OBS, so changes made in OBS are kept. To set them again if settings were changed for some reason, close OBS and run the following in a normal PowerShell. It changes only these video settings, in every OBS profile, and does not run the rest of the setup.
* **Reset OBS Video Settings**
    ```powershell
    cd c:\church-obs-setup
    powershell -ExecutionPolicy Bypass -File .\tools\set-obs-video.ps1
    ```