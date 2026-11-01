# Ubuntu Script Instructions

# Scene Collection information
  There are three total Scene collections you can install - single camera, dual camera and stake conference - depending on the number of cameras installed in your building and if you need the additional scenes used for stake conference broadcasts
  use the code labeled below for the scene collection you want to install
  The single camera Scene Collection is intended for use in the Alkire and Quail Building
  The Dual Camera Scene Collection is intended for use in the Independence Building (Stake Center)
  The Stake Conference Scene Collection is intended for use for meetings where an additional computer will be generating and sending overlay graphics to OBS using NDI. It is based on the Dual Camera Scene Collection. If it is being used in the Alkire or Quail buildings for a meeting ONLY the scenes labeled left will work correctly

# First Time Ubuntu Install
  1. Open Terminal
  2. Run one of the following depending on required camera configuration for your building
* **Single Camera Configuration**
    ```terminal
    cd ~
    sudo git clone https://github.com/smitchell7/church-obs-setup.git
    cd church-obs-setup
    sudo ./setup-obs-flatpak.sh --config=single-camera --pin-dock
    ```
* **Dual Camera Configuration**
    ```terminal
    cd ~
    sudo git clone https://github.com/smitchell7/church-obs-setup.git
    cd church-obs-setup
    sudo ./setup-obs-flatpak.sh --config=dual-camera --pin-dock
    ```
* **Stake Conference Camera Configuration**
    ```terminal
    cd ~
    sudo git clone https://github.com/smitchell7/church-obs-setup.git
    cd church-obs-setup
    sudo ./setup-obs-flatpak.sh --config=stake-conference --pin-dock

# Updating configuraiton on Existing Installations
* the first time you do this you may need to start with the following command:
    ```terminal
    cd ~/church-obs-setup
    sudo chown -R test:test ~/church-obs-setup
    ```

* **Single Camera Configuration**
    ```terminal
    cd church-obs-setup
    git checkout main
    git pull
    sudo ./setup-obs-flatpak.sh --config=single-camera
    ```
* **Dual Camera Configuration**
    ```terminal
    cd church-obs-setup
    git checkout main
    git pull
    sudo ./setup-obs-flatpak.sh --config=dual-camera
    ```
  * **Dual Camera Configuration**
    ```terminal
    cd church-obs-setup
    git checkout main
    git pull
    sudo ./setup-obs-flatpak.sh --config=stake-conference
    ```  
If you need to add one of the scene collections you do not currently have, run the update script for the scene collection you want to add to your computer
