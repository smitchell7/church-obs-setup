# Ubuntu Script Instructions

  # Scene Collection Note
  There are two Scene collections you can install depending on your building camera configuration and one scene collection that is intended for use at stake conference.
  Use the single camera setup code to install the single camera Scene Collection and the dual camera code to install the dual camera configuration.
  The single camera Scene Collection is what is wanted for the Alkire and Quail Buildings
  The Dual Camera Scene Collection is what is wanted for the Independence Building (Stake Center)
  The Stake Conference Scene Collection is intended only for use for meetings where an additional computer will be generating and sending overlay graphics to OBS over NDI. It is based on the Dual Camera Scene Collection

  # First Time Ubuntu Install
1. Open Terminal
2. paste the command corosponding to the required scene Collection
  * **Single Camera Configuration**
  ```terminal
  cd ~
  sudo git clone https://github.com/smitchell7/church-obs-setup.git
  cd church-obs-setup
  sudo ./setup-obs-flatpak.sh --config=single-camera
  ```
  * **Dual Camera Configuration**
  ```terminal
  cd ~
  sudo git clone https://github.com/smitchell7/church-obs-setup.git
  cd church-obs-setup
  sudo ./setup-obs-flatpak.sh --config=dual-camera
  ```
  * **Stake Conference Camera Configuration**
  ```terminal
  cd ~
  sudo git clone https://github.com/smitchell7/church-obs-setup.git
  cd church-obs-setup
  sudo ./setup-obs-flatpak.sh --config=stake-conference
  ```
