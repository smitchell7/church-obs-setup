# Ubuntu Script Instructions

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
  `setup-obs-flatpak.sh` installs Downstream Keyer from the Flatpak attached to the newest release of a fork on GitHub (https://github.com/harmanmj/obs-downstream-keyer) instead of from Flathub. The fork adds the Load On Scene option (a keyer can be set to show only on the program scenes you choose) and Go Live / Go to Preview controls that work with Studio Mode.
  Each time the setup script runs, it downloads the newest release, installs it if Downstream Keyer is missing, and replaces it if it came from Flathub or from an older release. If the fork has no Flatpak published, the Flathub version is used. If the computer can't reach GitHub, the Downstream Keyer already installed is kept.

# First Time Ubuntu Install
  1. Open Terminal
  2. Run the following, then type the number of the scene collection OBS should open on when it asks
    ```terminal
    cd ~
    git clone https://github.com/smitchell7/church-obs-setup.git
    cd ~/church-obs-setup
    sudo ./setup-obs-flatpak.sh
    ```
  Clone it **without** sudo, so the folder belongs to you and later updates need no sudo for `git pull`.

# Running Updates on an existing installation
* **Update** (asks which scene collection OBS should open on; press Enter to keep the current one)
    ```terminal
    cd ~/church-obs-setup
    git checkout main
    git pull
    sudo ./setup-obs-flatpak.sh
    ```
  **If `git pull` fails** with "Permission denied", "insufficient permission" or "detected dubious ownership": the computer was probably installed with `sudo git clone` (older instructions), which left `~/church-obs-setup` owned by root. Nothing needs it to be owned by root. Give the folder back to yourself once, then run the steps above again (the setup script also fixes this each time it runs):
    ```terminal
    sudo chown -R $USER:$USER ~/church-obs-setup
    ```

# OBS Configuration Reset Button (no terminal or password needed)
The setup script adds an **OBS Configuration Reset** button to the app menu and pins it to the dock next to OBS. One click does the same as the terminal steps below: it downloads the latest version of `~/church-obs-setup` from GitHub, asks in a window which scene collection OBS should open on (the current one is already selected), and puts the scene collections and OBS configuration back to the defaults. The cameras, microphone and NDI sources picked in OBS are kept. It needs no sudo password and no terminal, and it never installs or updates software.
* Close OBS first. If OBS is open, the button says so and does nothing.
* If something goes wrong, the button shows the details. The output of the last run is in `~/.cache/church-obs-config-update.log`.
* It updates the copy in `~/church-obs-setup`, on the branch it is on.

# Updating Only the Scene Collections and OBS Configuration
The **OBS Configuration Reset** button does this in one click. To do it in a terminal instead:

Use this when only the scene collections have changed. It installs the newest version of every scene collection in `obs-configuration/` without running the rest of the setup (no software is installed). The devices already picked in OBS (the cameras, the USB Audio microphone and the FreeShow NDI sources) are kept, and each collection it replaces is saved as a `.bak` file. It also builds the notch filter plugins used on USB Audio if they are missing, and makes sure OBS can find them (no sudo needed). It points OBS's audio monitoring at the speaker that feeds Zoom, and turns on OBS's WebSocket server for remote control (keeping its password). The video settings are left as they are. It puts back the OBS window layout (`obs-configuration/obs-layout.ini`), so docks closed or moved by accident come back. It turns Studio Mode on. Close OBS, then run the following in a normal terminal, without sudo:
* **Update the Scene Collections** (asks which scene collection OBS should open on; press Enter to keep the current one)
    ```terminal
    cd ~/church-obs-setup
    git checkout main
    git pull
    python3 tools/obs-config-update.py
    ```
  **If `git pull` fails** with "Permission denied", "insufficient permission" or "detected dubious ownership": the computer was probably installed with `sudo git clone` (older instructions), which left `~/church-obs-setup` owned by root. Nothing needs it to be owned by root. Give the folder back to yourself once, then run the steps above again (the setup script also fixes this each time it runs):
    ```terminal
    sudo chown -R $USER:$USER ~/church-obs-setup
    ```

# Resetting OBS Video Settings
The video settings (1920x1080 canvas and output, 30 fps, recording quality "Same as stream") are only set the first time the script sets up OBS, so changes made in OBS are kept. To set them again if settings were changed for some reason, close OBS and run the following in a normal terminal, without sudo. It changes only these video settings, in every OBS profile, and does not run the rest of the setup.
* **Reset OBS Video Settings**
    ```terminal
    cd ~/church-obs-setup
    python3 tools/set-obs-video.py
    ```