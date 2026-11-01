<#
.SYNOPSIS
  Set up a Windows computer for the church broadcast in one run: install everything, then configure it.
  (Windows twin of setup-obs-flatpak.sh.)

.DESCRIPTION
  1. Git (via winget), then this repo: cloned to C:\church-obs-setup, or updated with git pull if it is
     already there. The rest of the run uses that checkout, so the computer always runs the current version.
  2. OBS Studio 33+ (via winget)
  3. NDI Runtime 6.3+ (via winget); on Windows it already decodes HX2/HX3 cameras
  4. DistroAV (NDI) and obs-ptz (PTZ Controls), latest releases from GitHub
  5. ffmpeg (via winget) and VB-Audio Virtual Cable, the virtual microphone Zoom listens to
  6. OBS configuration: the scene collection from configs\<name>\ with the USB input picked, OBS's audio
     monitoring sent to the virtual cable, and a firewall rule for NDI
  7. The sacrament graphic and the sacrament music playlist in Documents\sacrament

  Run from an elevated PowerShell (right-click, Run as administrator), as the person who uses OBS:
    powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1 [-Config single-camera|dual-camera | -NoConfig]
  The script can be run again at any time; it installs only what is missing and refreshes the configuration.

.PARAMETER Config       Install the OBS scenes and camera setup in configs\<name> (asks if omitted).
.PARAMETER NoConfig     Skip the OBS scene collection.
.PARAMETER AudioDevice  The microphone input for OBS: part of its name as Windows shows it, or its endpoint id.
                        Default: the Sound Blaster, else any USB input, else the first other input that is
                        not NDI Webcam Audio or the virtual cable.
.PARAMETER PtzInstaller Use this obs-ptz installer .exe instead of the latest glikely/obs-ptz release.
.PARAMETER RepoUrl      Where to clone this repo from.
.PARAMETER Branch       Which branch of the repo to use.
.PARAMETER RepoDir      Where the checkout lives.
#>
param(
    [string]$Config,
    [switch]$NoConfig,
    [string]$AudioDevice,
    [string]$PtzInstaller,
    [string]$RepoUrl = 'https://github.com/smitchell7/church-obs-setup.git',
    [string]$Branch = 'windows',
    [string]$RepoDir = (Join-Path $env:SystemDrive 'church-obs-setup'),
    [switch]$FromCheckout   # internal: set when this script re-runs itself from the checkout
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # makes Invoke-WebRequest much faster
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# DistroAV 6.2.2 installs to the OBS 33+ plugin location, and obs-ptz needs 32+; require 33.
$MinObs = [version]'33.0.0'
$ObsExe = Join-Path $env:ProgramFiles 'obs-studio\bin\64bit\obs64.exe'
$VbCableZip = 'https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack45.zip'

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Fail 'Please run this from an elevated PowerShell (right-click, Run as administrator).' }
if (Get-Process obs64 -ErrorAction SilentlyContinue) { Fail 'OBS is running. Close it and run this again.' }
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Fail 'winget was not found. Install "App Installer" from the Microsoft Store (or update Windows) and retry.'
}

function Winget-Run($wingetArgs) {
    & winget @wingetArgs --silent --accept-package-agreements --accept-source-agreements
    # -1978335189 = no applicable upgrade, -1978335135 = already installed: both fine
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189 -and $LASTEXITCODE -ne -1978335135) {
        Fail "winget $($wingetArgs -join ' ') failed (exit $LASTEXITCODE)."
    }
}

# winget installs change PATH for new sessions only; pick it up in this one too.
function Update-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

# ---- 1. Git and this repo ----------------------------------------------------
if (-not $FromCheckout) {
    Step '[1/7] Git and the setup repo'
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host '    Git is not installed; installing.'
        Winget-Run @('install', '--id', 'Git.Git', '--exact')
        Update-Path
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            $gitExe = Join-Path $env:ProgramFiles 'Git\cmd'
            if (Test-Path (Join-Path $gitExe 'git.exe')) { $env:Path += ";$gitExe" }
        }
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'Git was installed but cannot be found; open a new PowerShell and run this again.' }
    }
    Write-Host "    $(git --version)"
    if (Test-Path (Join-Path $RepoDir '.git')) {
        Write-Host "    Updating $RepoDir"
        & git -C $RepoDir fetch --quiet origin
        if ($LASTEXITCODE -ne 0) { Fail "git fetch failed in $RepoDir." }
        & git -C $RepoDir checkout --quiet $Branch
        if ($LASTEXITCODE -ne 0) { Fail "Could not switch $RepoDir to branch $Branch (local changes there?)." }
        & git -C $RepoDir pull --quiet --ff-only origin $Branch
        if ($LASTEXITCODE -ne 0) { Fail "git pull failed in $RepoDir (local changes there?). Fix or remove that folder and retry." }
    } elseif (Test-Path $RepoDir) {
        Fail "$RepoDir exists but is not a git checkout. Move it away (or pass -RepoDir) and run this again."
    } else {
        Write-Host "    Cloning $RepoUrl ($Branch) to $RepoDir"
        & git clone --quiet --branch $Branch $RepoUrl $RepoDir
        if ($LASTEXITCODE -ne 0) { Fail "git clone of $RepoUrl failed." }
    }
    Write-Host "    At $(git -C $RepoDir log -1 --format='%h %s')"

    # Carry on with the checkout's copy of this script, so the run always matches the repo it configures from.
    $again = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $RepoDir 'setup-obs-windows.ps1'), '-FromCheckout')
    foreach ($p in 'Config', 'AudioDevice', 'PtzInstaller') {
        $v = Get-Variable $p -ValueOnly
        if ($v) { $again += @("-$p", $v) }
    }
    if ($NoConfig) { $again += '-NoConfig' }
    & (Get-Process -Id $PID).Path @again
    exit $LASTEXITCODE
}
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---- 2. OBS Studio -----------------------------------------------------------
function Get-ObsVersion {
    if (-not (Test-Path $ObsExe)) { return $null }
    $v = (Get-Item $ObsExe).VersionInfo
    return [version]('{0}.{1}.{2}' -f $v.FileMajorPart, $v.FileMinorPart, $v.FileBuildPart)
}

# Apps that list webcams (browsers, Teams, Zoom, Claude...) load OBS's virtual-camera
# DLL, which locks files the OBS installer must replace (it fails with exit code 6).
function Get-ObsFileHolders {
    $obsDir = Join-Path $env:ProgramFiles 'obs-studio'
    Get-Process | Where-Object {
        $_.Id -ne $PID -and $(try { $_.Modules | Where-Object { $_.FileName -like "$obsDir\*" } } catch { $null })
    }
}

function Clear-ObsFileHolders {
    $holders = @(Get-ObsFileHolders)
    if (-not $holders) { return }
    Write-Host '    These apps have OBS files open (usually the OBS virtual camera) and block the upgrade:' -ForegroundColor Yellow
    $holders | ForEach-Object { Write-Host "      - $($_.Name) (pid $($_.Id))" }
    $answer = Read-Host '    Close them now? Unsaved work in them will be lost. [y/N]'
    if ($answer -notmatch '^(y|yes)$') { Fail 'Close the apps listed above and run this again.' }
    $holders | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $left = @(Get-ObsFileHolders)
    if ($left) { Fail "Still open: $(($left | ForEach-Object Name) -join ', '). Close them (or reboot) and run this again." }
}

Step '[2/7] OBS Studio'
$have = Get-ObsVersion
if ($have -and $have -ge $MinObs) {
    Write-Host "    OBS $have is new enough."
} else {
    if ($have) {
        Write-Host "    OBS $have is older than $MinObs; upgrading."
        Clear-ObsFileHolders
        Winget-Run @('upgrade', '--id', 'OBSProject.OBSStudio', '--exact')
    } else {
        Write-Host '    OBS is not installed; installing.'
        Winget-Run @('install', '--id', 'OBSProject.OBSStudio', '--exact')
    }
    $have = Get-ObsVersion
    if (-not $have -or $have -lt $MinObs) {
        Fail "OBS is $have after winget; need $MinObs or newer. Install it from https://obsproject.com/download and re-run."
    }
    Write-Host "    OBS $have installed."
}

# ---- 3. NDI Runtime ----------------------------------------------------------
Step '[3/7] NDI Runtime (needed by DistroAV)'
function Find-Ndi {
    $dir = [Environment]::GetEnvironmentVariable('NDILIB_REDIST_FOLDER', 'Machine')
    return ($dir -and (Test-Path (Join-Path $dir 'Processing.NDI.Lib.x64.dll')))
}
if (Find-Ndi) {
    Write-Host '    NDI Runtime is installed.'
} else {
    Winget-Run @('install', '--id', 'NDI.NDIRuntime', '--exact')
    if (-not (Find-Ndi)) { Write-Warning 'NDI Runtime installed, but its folder is not registered yet; a restart may be needed.' }
}

# ---- 4. Plugins --------------------------------------------------------------
function Install-Exe($file) {
    $p = Start-Process $file -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-' -Wait -PassThru
    if ($p.ExitCode -ne 0) { Fail "$file failed (exit $($p.ExitCode))." }
}

function Install-FromGitHub($repo, $pattern, $label, [switch]$IncludePrerelease) {
    $headers = @{ 'User-Agent' = 'church-obs-setup' }
    if ($IncludePrerelease) {
        $releases = Invoke-RestMethod "https://api.github.com/repos/$repo/releases" -Headers $headers
    } else {
        $releases = @(Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers $headers)
    }
    foreach ($r in $releases) {
        if ($r.draft) { continue }
        $asset = $r.assets | Where-Object { $_.name -like $pattern } | Select-Object -First 1
        if ($asset) {
            Write-Host "    $label $($r.tag_name)"
            $file = Join-Path $env:TEMP $asset.name
            Invoke-WebRequest $asset.browser_download_url -OutFile $file -UseBasicParsing
            Install-Exe $file
            return
        }
    }
    Fail "No $label Windows installer found in $repo releases."
}

Step '[4/7] DistroAV (NDI) and obs-ptz (PTZ Controls)'
Install-FromGitHub 'DistroAV/DistroAV' 'distroav-*-windows-x64-Installer.exe' 'DistroAV'
if ($PtzInstaller) {
    if (-not (Test-Path $PtzInstaller)) { Fail "No such file: $PtzInstaller" }
    Install-Exe $PtzInstaller
} else {
    # Upstream only publishes pre-releases (1.0 betas) so far; take the newest. It uses the same preset
    # format (camera:N, device_uuid) as the configs here.
    Install-FromGitHub 'glikely/obs-ptz' 'obs-ptz-*-windows-x64-Installer.exe' 'obs-ptz' -IncludePrerelease
}

# ---- 5. Audio tools: ffmpeg and the virtual cable ------------------------------
# Windows lists audio devices ("endpoints") under MMDevices. An endpoint's id, as OBS stores it, is
# {0.0.1.00000000}.{guid} for an input and {0.0.0.00000000}.{guid} for an output.
$MMDev = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio'
function Get-AudioEndpoints($kind) {   # 'Capture' (inputs) or 'Render' (outputs)
    $prefix = if ($kind -eq 'Capture') { '{0.0.1.00000000}.' } else { '{0.0.0.00000000}.' }
    foreach ($k in Get-ChildItem (Join-Path $MMDev $kind) -ErrorAction SilentlyContinue) {
        $state = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).DeviceState
        if ($state -ne 1) { continue }   # 1 = active (present and enabled)
        $props = Get-ItemProperty (Join-Path $k.PSPath 'Properties') -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        $desc = $props.'{a45c254e-df1c-4efd-8020-67d146a850e0},2'    # e.g. "Microphone", "CABLE Input"
        $iface = $props.'{b3f8fa53-0004-438e-9003-51a46e139bfc},6'   # e.g. "Sound Blaster Play! 3"
        [pscustomobject]@{ Id = $prefix + $k.PSChildName; Name = "$desc ($iface)"; Description = $desc }
    }
}
function Find-CableInput { Get-AudioEndpoints 'Render' | Where-Object Description -like 'CABLE Input*' | Select-Object -First 1 }

Step '[5/7] ffmpeg (for the sacrament playlist) and VB-Audio Virtual Cable (for Zoom)'
function Find-Ffmpeg {
    $c = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($p in @((Join-Path $env:ProgramFiles 'WinGet\Links\ffmpeg.exe'),
                     (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\ffmpeg.exe'))) {
        if (Test-Path $p) { return $p }
    }
    $found = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages') -Filter ffmpeg.exe -Recurse -ErrorAction SilentlyContinue |
             Where-Object FullName -like '*Gyan.FFmpeg*' | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}
$Ffmpeg = Find-Ffmpeg
if ($Ffmpeg) {
    Write-Host "    ffmpeg: $Ffmpeg"
} else {
    Winget-Run @('install', '--id', 'Gyan.FFmpeg', '--exact')
    Update-Path
    $Ffmpeg = Find-Ffmpeg
    if ($Ffmpeg) { Write-Host "    ffmpeg: $Ffmpeg" } else { Write-Warning 'ffmpeg was installed but cannot be found; the playlist will be built on the next run.' }
}

$CableNeedsReboot = $false
if (Find-CableInput) {
    Write-Host '    VB-Audio Virtual Cable is installed.'
} elseif (Get-PnpDevice -FriendlyName '*VB-Audio Virtual Cable*' -ErrorAction SilentlyContinue) {
    $CableNeedsReboot = $true
    Write-Warning 'VB-Audio Virtual Cable is installed but not active yet: restart Windows, then run this again.'
} else {
    # VB-CABLE is donationware with its own licence (https://vb-audio.com/Services/licensing.htm), so its
    # setup runs visibly: click "Install Driver" and accept. It is downloaded from the vendor, not kept here.
    Write-Host '    Installing VB-Audio Virtual Cable: in its window, click "Install Driver" and accept.'
    $zip = Join-Path $env:TEMP 'VBCABLE_Driver_Pack.zip'
    $dir = Join-Path $env:TEMP 'VBCABLE_Driver_Pack'
    Invoke-WebRequest $VbCableZip -OutFile $zip -UseBasicParsing
    Expand-Archive $zip -DestinationPath $dir -Force
    Start-Process (Join-Path $dir 'VBCABLE_Setup_x64.exe') -Wait
    if (Find-CableInput) {
        Write-Host '    VB-Audio Virtual Cable is ready.'
    } else {
        $CableNeedsReboot = $true
        Write-Warning 'VB-Audio Virtual Cable needs a restart of Windows to finish installing. Restart, then run this again.'
    }
}

# ---- 6. OBS configuration -----------------------------------------------------
Step '[6/7] OBS configuration'
if (-not (Get-NetFirewallRule -DisplayName 'OBS Studio (church setup)' -ErrorAction SilentlyContinue)) {
    # NDI discovery (mDNS) and video need OBS reachable on the LAN
    New-NetFirewallRule -DisplayName 'OBS Studio (church setup)' -Direction Inbound -Action Allow `
        -Program $ObsExe -Profile Any | Out-Null
}

$configRoot = Join-Path $ScriptDir 'configs'
$configs = @()
if (Test-Path $configRoot) { $configs = @(Get-ChildItem $configRoot -Directory | ForEach-Object Name) }
if ($NoConfig) {
    $Config = $null
} elseif (-not $Config) {
    if ($configs.Count -eq 0 -or -not [Environment]::UserInteractive) {
        Write-Host '    No -Config given and nothing to ask; skipping the OBS scene collection.'
    } else {
        Write-Host 'Which camera setup should be installed?'
        for ($i = 0; $i -lt $configs.Count; $i++) { Write-Host "  $($i + 1)) $($configs[$i])" }
        Write-Host "  $($configs.Count + 1)) none (set OBS up by hand)"
        do {
            $n = Read-Host 'Number'
        } until ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $configs.Count + 1)
        if ([int]$n -le $configs.Count) { $Config = $configs[[int]$n - 1] }
    }
}

$ObsDir = Join-Path $env:APPDATA 'obs-studio'
$docs = [Environment]::GetFolderPath('MyDocuments')
$MusicDir = Join-Path $docs 'sacrament'
New-Item -ItemType Directory -Force $MusicDir | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false

if ($Config) {
    $src = Join-Path $configRoot $Config
    if (-not (Test-Path $src)) { Fail "No such configuration: $Config (have: $($configs -join ', '))" }

    # The microphone: the "USB Audio" source is a PulseAudio input in the repo; on Windows it is a WASAPI input.
    $inputs = @(Get-AudioEndpoints 'Capture' | Where-Object { $_.Description -notlike 'CABLE Output*' })
    $pick = $null
    if ($AudioDevice) {
        $pick = $inputs | Where-Object { $_.Id -eq $AudioDevice -or $_.Name -like "*$AudioDevice*" } | Select-Object -First 1
        if (-not $pick) { Write-Warning "No input matches '$AudioDevice'; using the Windows default input." }
    } else {
        # NDI Tools adds virtual "NDI Webcam Audio" inputs; their sound is poor, so never pick one by default.
        $real = @($inputs | Where-Object { $_.Name -notmatch 'NDI' })
        $pick = $real | Where-Object Name -match 'Sound Blaster' | Select-Object -First 1
        if (-not $pick) { $pick = $real | Where-Object Name -match 'USB' | Select-Object -First 1 }
        if (-not $pick) {
            Write-Warning 'No Sound Blaster or USB audio input is plugged in. Plug it in and run this again, or pass -AudioDevice.'
            # Else any real input, by id: "default" could be CABLE Output or NDI audio.
            $pick = $real | Select-Object -First 1
        }
    }
    $deviceId = if ($pick) { $pick.Id } else { 'default' }
    $deviceName = if ($pick) { $pick.Name } else { 'the Windows default input' }
    Write-Host "    Audio input for OBS: $deviceName (change it on the 'USB Audio' source in OBS if this is wrong)"

    $scenes = Join-Path $ObsDir 'basic\scenes'
    New-Item -ItemType Directory -Force $scenes | Out-Null
    # OBS accepts forward slashes in paths, and they need no JSON escaping
    $sacramentFwd = $MusicDir -replace '\\', '/'
    foreach ($f in Get-ChildItem $src -Filter *.json) {
        $dest = Join-Path $scenes $f.Name
        if (Test-Path $dest) { Copy-Item $dest "$dest.$(Get-Date -Format yyyyMMdd-HHmmss).bak" }
        $text = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
        # Documents may be redirected to OneDrive here; the DejaVu Serif font is Linux-only, so use Georgia
        $text = $text.Replace('@HOME@/Documents/sacrament', $sacramentFwd).Replace('DejaVu Serif', 'Georgia')
        $text = $text.Replace('"id": "pulse_input_capture"', '"id": "wasapi_input_capture"')
        $text = $text.Replace('"versioned_id": "pulse_input_capture"', '"versioned_id": "wasapi_input_capture"')
        $text = $text.Replace('@AUDIO_DEVICE@', $deviceId)
        [IO.File]::WriteAllText($dest, $text, $utf8)
    }
    Write-Host "    Installed the '$Config' scene collection. In OBS choose it from the Scene Collection menu."
}

# Zoom audio: OBS monitors "USB Audio" and "Sacrament Music" (Monitor and Output, set in the configs) into the
# virtual cable's input; Zoom's microphone is the cable's output, "CABLE Output (VB-Audio Virtual Cable)".
function Set-IniValues($path, $section, [hashtable]$values) {
    $lines = if (Test-Path $path) { [IO.File]::ReadAllLines($path) } else { @() }
    $out = New-Object System.Collections.Generic.List[string]
    $done = @{}; $inSection = $false; $seen = $false
    $flush = { foreach ($k in $values.Keys) { if (-not $done[$k]) { $out.Add("$k=$($values[$k])"); $done[$k] = $true } } }
    foreach ($l in $lines) {
        if ($l -match '^\s*\[(.+)\]\s*$') {
            if ($inSection) { & $flush }
            $inSection = ($Matches[1] -eq $section)
            if ($inSection) { $seen = $true }
        } elseif ($inSection -and $l -match '^([^=;#]+)=') {
            $k = $Matches[1].Trim()
            if ($values.ContainsKey($k)) { $out.Add("$k=$($values[$k])"); $done[$k] = $true; continue }
        }
        $out.Add($l)
    }
    if ($inSection) { & $flush }
    if (-not $seen) { $out.Add("[$section]"); & $flush }
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    [IO.File]::WriteAllLines($path, $out.ToArray(), $utf8)
}

$cable = Find-CableInput
if ($cable) {
    $profiles = @(Get-ChildItem (Join-Path $ObsDir 'basic\profiles') -Directory -ErrorAction SilentlyContinue)
    if ($profiles.Count -eq 0) {
        # OBS has never run: make a "Church" profile and select it
        $profiles = @([pscustomobject]@{ FullName = (Join-Path $ObsDir 'basic\profiles\Church'); Name = 'Church' })
        Set-IniValues (Join-Path $ObsDir 'user.ini') 'Basic' @{ Profile = 'Church'; ProfileDir = 'Church' }
        Set-IniValues (Join-Path $profiles[0].FullName 'basic.ini') 'General' @{ Name = 'Church' }
    }
    foreach ($p in $profiles) {
        Set-IniValues (Join-Path $p.FullName 'basic.ini') 'Audio' @{ MonitoringDeviceId = $cable.Id; MonitoringDeviceName = $cable.Name }
        Write-Host "    OBS monitoring device ($($p.Name)): $($cable.Name)"
    }
} else {
    Write-Warning 'The virtual cable is not active yet, so OBS monitoring was not pointed at it. Restart Windows and run this again.'
}

# Open OBS in studio mode. OBS saves this on exit, so it is only the starting state.
Set-IniValues (Join-Path $ObsDir 'user.ini') 'BasicWindow' @{ PreviewProgramMode = 'true' }

# ---- 7. Sacrament graphic and music playlist -----------------------------------
Step '[7/7] Sacrament graphic and music playlist'
$graphic = Join-Path $MusicDir 'sacrament-graphic.png'
if (Test-Path $graphic) {
    Write-Host '    The sacrament graphic is already there.'
} else {
    try {
        & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'tools\make-sacrament-graphic.ps1') -Out $graphic
        if ($LASTEXITCODE -ne 0) { throw "exit $LASTEXITCODE" }
    } catch {
        Write-Warning "Could not make the sacrament graphic ($_); see tools\make-sacrament-graphic.ps1"
    }
}
if ($Ffmpeg) {
    # The hymns in audio\sacrament-playlist.txt, joined into one file that OBS loops.
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'tools\make-sacrament-playlist.ps1') `
        -List (Join-Path $ScriptDir 'audio\sacrament-playlist.txt') -Dir $MusicDir -Ffmpeg $Ffmpeg
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not build the sacrament playlist; see tools\make-sacrament-playlist.ps1' }
} else {
    Write-Warning 'No ffmpeg, so the sacrament playlist was not built. Run this again.'
}

if ($CableNeedsReboot) {
    Write-Host '==> Almost done: restart Windows, then run this script again to point OBS at the virtual cable.' -ForegroundColor Yellow
} else {
    Write-Host '==> Done. Start OBS from the Start menu; in Zoom pick the microphone "CABLE Output (VB-Audio Virtual Cable)".' -ForegroundColor Green
}
