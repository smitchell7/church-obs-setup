# Windows Script Instructions

# Scene Collection information
  There are three total Scene collections you can install - single camera, dual camera and stake conference - depending on the number of cameras installed in your building and if you need the additional scenes used for stake conference broadcasts
  use the code labeled below for the scene collection you want to install
  The single camera Scene Collection is intended for use in the Alkire and Quail Building
  The Dual Camera Scene Collection is intended for use in the Independence Building (Stake Center)
  The Stake Conference Scene Collection is intended for use for meetings where an additional computer will be generating and sending overlay graphics to OBS using NDI. It is based on the Dual Camera Scene Collection. If it is being used in the Alkire or Quail buildings for a meeting ONLY the scenes labeled left will work correctly

# First Time Windows Install

  1. Open **PowerShell as administrator** (Start, type `powershell`, right-click > Run as administrator)
  2. Run one of the following depending on required camera configuration for your building
* **Single Camera Configuration**
    ```powershell
    cd $env:TEMP
    irm https://raw.githubusercontent.com/smitchell7/church-obs-setup/HEAD/setup-obs-windows.ps1 -OutFile setup-obs-windows.ps1
    powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1 -Config single-camera
    ```
    
* **Dual Camera Configuration**
    ```powershell
    cd $env:TEMP
    irm https://raw.githubusercontent.com/smitchell7/church-obs-setup/HEAD/setup-obs-windows.ps1 -OutFile setup-obs-windows.ps1
    powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1 -Config dual-camera
    ```
    
* **Stake Conference Camera Configuration**
    ```powershell
    cd $env:TEMP
    irm https://raw.githubusercontent.com/smitchell7/church-obs-setup/HEAD/setup-obs-windows.ps1 -OutFile setup-obs-windows.ps1
    powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1 -Config Stake-Conference
    ```

# Updating configuraiton on Existing Installations
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
If you need to add one of the scene collections you do not currently have, run the update script for the scene collection you want to add to your computer
