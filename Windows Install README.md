# Windows Script Instructions

  # Scene Collection Note
  There are two Scene collections you can install depending on your building camera configuration
  Use the single camera setup code to install the single camera Scene Collection and the dual camera code to install the dual camera configuration
  The single camera Scene Collection is what is wanted for the Alkire and Quail Buildings
  The Dual Camera Scene Collection is what is wanted for the Independence Building (Stake Center)

# First Time Windows Install

  1. Open **PowerShell as administrator** (Start, type `powershell`, right-click > Run as administrator)
  2A. Single Camera Configuration
   ```powershell
   cd $env:TEMP
   irm https://raw.githubusercontent.com/smitchell7/church-obs-setup/windows/setup-obs-windows.ps1 -OutFile setup-obs-windows.ps1
   powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1 -Config single-camera
  ```
  2B. Dual Camera Configuration
   ```powershell
   cd $env:TEMP
   irm https://raw.githubusercontent.com/smitchell7/church-obs-setup/windows/setup-obs-windows.ps1 -OutFile setup-obs-windows.ps1
   powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1 -Config dual-camera
   ```
# Updating to the Latest Configurations
Single Camera Configuration
   ```powershell
  cd c:\church-obs-setup
  git pull
  powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1 -Config single-camera
   ```
Dual Camera Configuration
   ```powershell
  cd c:\church-obs-setup
  git pull
  powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1 -Config dual-camera
   ```
If you need to add the scene collection you do not currently have run the update script for the scene collection you want to add to your computer
