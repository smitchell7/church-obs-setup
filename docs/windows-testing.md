# Testing the Windows setup

`setup-obs-windows.ps1` has not yet been run on Windows. This page has two parts: preparing a spare
Windows laptop so the scripts can be run and checked over SSH from the Linux broadcast laptop, and the
test plan.

The first run on a laptop is the only "new computer" test it gets, so prepare the laptop first and start
the test plan on a machine that has never had OBS, NDI or VB-CABLE installed, if possible.

## Part 1: prepare the test laptop (about 10 minutes, at the laptop)

1. Sign in with the account that will use OBS. It must be an **administrator** (Settings > Accounts >
   Other users / Your info shows "Administrator"). The setup script writes OBS's settings for the account
   that runs it.
2. Connect it to the church network (the same one as the cameras and the Linux laptop).
3. Stop it sleeping while plugged in: Settings > System > Power > Screen and sleep > "Never" when plugged in.
4. Open **PowerShell as administrator** (Start, type `powershell`, right-click > Run as administrator) and
   paste this whole block. It turns on Windows' built-in SSH server, allows the Linux laptop's test key to
   sign in, and makes PowerShell the shell for SSH sessions:

   ```powershell
   # OpenSSH server (built into Windows 10/11)
   Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
   Set-Service sshd -StartupType Automatic
   Start-Service sshd
   if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
       New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
           -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
   }

   # The Linux broadcast laptop's test key (a public key: safe to share). For administrator accounts
   # Windows reads keys from this file, and only if just Administrators and SYSTEM can access it.
   $key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDrKn4aezKEjEHkqyZbWjxMubaEtDb24/mwFxxCnMo8V claude-windows-test@arvada-stake-pw01drk5'
   $auth = 'C:\ProgramData\ssh\administrators_authorized_keys'
   Add-Content -Path $auth -Value $key
   icacls $auth /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null

   # PowerShell, not cmd, for SSH sessions
   New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell `
       -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force | Out-Null

   # What to send back: the user name and the address
   "User: $env:USERNAME"
   Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
       Select-Object InterfaceAlias, IPAddress
   ```

5. Send back the **user name** and the **IP address** it printed (the Wi-Fi or Ethernet one, e.g.
   `192.168.108.x`).
6. Leave the laptop signed in, with the lid open or a screen attached. Two steps need someone at it once:
   accepting the VB-CABLE licence, and a restart. Steps that start OBS need the user signed in at the desktop.

To undo all this later: `Stop-Service sshd; Set-Service sshd -StartupType Disabled`, and delete
`C:\ProgramData\ssh\administrators_authorized_keys`.

## Part 2: test plan

Commands below are run over SSH from the Linux laptop (`ssh -i ~/.ssh/id_ed25519_windows-test USER@IP`)
unless they say "at the laptop".

### A. First run on a new computer

1. Download only the script and run it, as a fresh computer would:
   ```powershell
   cd $env:TEMP
   irm https://raw.githubusercontent.com/smitchell7/church-obs-setup/windows/setup-obs-windows.ps1 -OutFile setup-obs-windows.ps1
   powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1 -Config single-camera
   ```
2. Expect, in order: Git installed; the repo cloned to `C:\church-obs-setup` on branch `windows`; the script
   continuing from there (`[2/7]` onwards); OBS 33+, NDI Runtime, DistroAV, obs-ptz, ffmpeg installed.
3. **At the laptop:** the VB-CABLE window opens. Click "Install Driver" and accept. The script then says a
   restart is needed. Restart Windows and sign back in.
4. Run the script again (from `C:\church-obs-setup`, or the downloaded copy). Expect `git pull` to report
   nothing new, every install step to say "installed" / "new enough", the audio input chosen
   (Sound Blaster, USB, or default), and "OBS monitoring device ... CABLE Input (VB-Audio Virtual Cable)".

### B. Files it should leave

- `%APPDATA%\obs-studio\basic\scenes\single-camera.json`: valid JSON; "USB Audio" is `wasapi_input_capture`
  with the chosen `device_id`; "USB Audio" and "Sacrament Music" have `monitoring_type` 2 and
  `monitoring_enabled` true; no `@HOME@` or `@AUDIO_DEVICE@` left.
- `%APPDATA%\obs-studio\basic\profiles\*\basic.ini`: `[Audio]` has `MonitoringDeviceId` and
  `MonitoringDeviceName=CABLE Input (VB-Audio Virtual Cable)`.
- `Documents\sacrament\`: `sacrament-graphic.png`, `hymns\*.mp3` (8 hymns), `sacrament-playlist.mp3`
  (about 29 minutes).

### C. In OBS (at the laptop, or started over SSH)

1. Scene Collection > Single Camera. The scenes are Joystick, Pulpit - p0 ... Choir - p8, Sacrament.
2. Settings > Audio > Advanced > Monitoring Device is "CABLE Input (VB-Audio Virtual Cable)".
3. Edit > Advanced Audio Properties: "USB Audio" and "Sacrament Music" say "Monitor and Output".
4. The "USB Audio" source's device is the USB input; the PTZ Controls dock lists the camera.
5. The camera's NDI video shows (Windows firewall rule and NDI Runtime).

### D. Audio reaches Zoom's microphone

Record "CABLE Output (VB-Audio Virtual Cable)" (what Zoom hears) with ffmpeg while OBS runs, e.g.
`ffmpeg -f dshow -i audio="CABLE Output (VB-Audio Virtual Cable)" -t 5 cap.wav`, then check its level
(`ffmpeg -i cap.wav -af volumedetect -f null -`):

1. Sacrament scene: the music is heard.
2. Joystick scene: the music stops and the USB input is heard; the camera does not move.
3. Back to Sacrament: the music starts again; with the music's monitoring turned off for a moment, the
   recording is silent (no microphone under the music).
4. In Zoom: the microphone list has "CABLE Output (VB-Audio Virtual Cable)" and its level meter moves.

### E. Run again on a set-up computer

Run the script a third time: it should change nothing it does not need to, keep a `*.bak` of the scene
file, and not rebuild the playlist ("playlist is up to date").
