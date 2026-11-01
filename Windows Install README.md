# Windows Script Instructions

  # Scene Collection Note
  There are two Scene collections you can install depending on your building camera configuration and one scene collection that is intended for use at stake conference.
  Use the single camera setup code to install the single camera Scene Collection and the dual camera code to install the dual camera configuration.
  The single camera Scene Collection is what is wanted for the Alkire and Quail Buildings
  The Dual Camera Scene Collection is what is wanted for the Independence Building (Stake Center)
  The Stake Conference Scene Collection is intended only for use for meetings where an additional computer will be generating and sending overlay graphics to OBS over NDI. It is based on the Dual Camera Scene Collection

# First Time Windows Install

  1. Open **PowerShell as administrator** (Start, type `powershell`, right-click > Run as administrator)
  2. Run one of the following depending on desired camera configuration
* **Single Camera Configuration**
   ```powershell
   cd $env:TEMP
   irm https://raw.githubusercontent.com/smitchell7/church-obs-setup/windows/setup-obs-windows.ps1 -OutFile setup-obs-windows.ps1
   powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1 -Config single-camera
  ```
* **Dual Camera Configuration**
   ```powershell
   cd $env:TEMP
   irm https://raw.githubusercontent.com/smitchell7/church-obs-setup/main/setup-obs-windows.ps1 -OutFile setup-obs-windows.ps1
   powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1 -Config dual-camera
   ```

* **Stake Conference Camera Configuration**
   ```powershell
   cd $env:TEMP
   irm https://raw.githubusercontent.com/smitchell7/church-obs-setup/main/setup-obs-windows.ps1 -OutFile setup-obs-windows.ps1
   powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1 -Config Stake-Conference
   ```
# Updating configuraiton on Existing Installation
* **Single Camera Configuration**
   ```powershell
  cd c:\church-obs-setup
  powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1 -Config single-camera
   ```
* **Dual Camera Configuration**
   ```powershell
  cd c:\church-obs-setup
  powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1 -Config dual-camera
   ```
* **Stake Conference Camera Configuration**
   ```powershell
  cd c:\church-obs-setup
  powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1 -Config stake-conference
   ```
If you need to add the scene collection you do not currently have, run the update script for the scene collection you want to add to your computer
