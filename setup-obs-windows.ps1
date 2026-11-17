<#
.SYNOPSIS
  Set up a Windows computer for the church broadcast in one run: install everything, then configure it.
  (Windows twin of setup-obs-flatpak.sh.)

.DESCRIPTION
  1. Git (via winget), then this repo: cloned to C:\church-obs-setup, or updated with git pull if it is
     already there. The rest of the run uses that checkout, so the computer always runs the current version.
  2. OBS Studio 33+ (via winget)
  3. NDI Runtime 6.3+ (via winget); on Windows it already decodes HX2/HX3 cameras
  4. DistroAV (NDI), Downstream Keyer and obs-ptz (PTZ Controls), latest releases from GitHub. Downstream Keyer
     comes from the fork https://github.com/harmanmj/obs-downstream-keyer (adds Load On Scene), or from
     exeldro/obs-downstream-keyer when the fork has no release published
  5. ffmpeg (via winget) and VB-Audio Virtual Cable, the virtual microphone Zoom listens to
  6. OBS configuration: every scene collection in obs-configuration\, with the chosen one set as the default, with the USB input picked, OBS's audio
     monitoring sent to the virtual cable, the window layout with PTZ Controls docked, and a firewall rule
     for NDI
  7. The sacrament graphic and the sacrament music playlist in Documents\sacrament

  Run from an elevated PowerShell (right-click, Run as administrator), as the person who uses OBS:
    powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1 [-Config FOLDER | -NoConfig]
  The script can be run again at any time; it installs only what is missing and refreshes the configuration.

.PARAMETER Config       Every scene collection in obs-configuration\ is installed; this is the one OBS opens on by
                        default: a collection folder in obs-configuration, e.g. sacrament-independence (if omitted: asks, with the current one marked; Enter keeps it).
.PARAMETER NoConfig     Skip the OBS scene collections.
.PARAMETER AudioDevice  The microphone input for OBS: part of its name as Windows shows it, or its endpoint id.
                        Default: the Sound Blaster, else any USB input, else the first other input that is
                        not NDI Webcam Audio or the virtual cable.
.PARAMETER PtzInstaller Use this obs-ptz installer .exe instead of the latest glikely/obs-ptz release.
.PARAMETER DskRepo      The GitHub repo to install Downstream Keyer from. Default: harmanmj/obs-downstream-keyer;
                        exeldro/obs-downstream-keyer goes back to the original.
.PARAMETER RepoUrl      Where to clone this repo from.
.PARAMETER Branch       Which branch of the repo to use. Default: the repo's default branch on GitHub.
.PARAMETER RepoDir      Where the checkout lives.
#>
param(
    [string]$Config,
    [switch]$NoConfig,
    [string]$AudioDevice,
    [string]$PtzInstaller,
    [string]$DskRepo = 'harmanmj/obs-downstream-keyer',
    [string]$RepoUrl = 'https://github.com/smitchell7/church-obs-setup.git',
    [string]$Branch,
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
    # Name the source: a Microsoft Store source that cannot be reached fails the whole command otherwise.
    & winget @wingetArgs --source winget --silent --accept-package-agreements --accept-source-agreements
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
        if (-not $Branch) {
            # No -Branch: follow the remote's default branch, which may have changed since the clone.
            & git -C $RepoDir remote set-head origin --auto *> $null
            $Branch = (& git -C $RepoDir symbolic-ref --short refs/remotes/origin/HEAD) -replace '^origin/', ''
            if ($LASTEXITCODE -ne 0 -or -not $Branch) { Fail "Could not find the default branch of origin in $RepoDir." }
        }
        & git -C $RepoDir checkout --quiet $Branch
        if ($LASTEXITCODE -ne 0) { Fail "Could not switch $RepoDir to branch $Branch (local changes there?)." }
        & git -C $RepoDir pull --quiet --ff-only origin $Branch
        if ($LASTEXITCODE -ne 0) { Fail "git pull failed in $RepoDir (local changes there?). Fix or remove that folder and retry." }
    } elseif (Test-Path $RepoDir) {
        Fail "$RepoDir exists but is not a git checkout. Move it away (or pass -RepoDir) and run this again."
    } else {
        if ($Branch) {
            Write-Host "    Cloning $RepoUrl ($Branch) to $RepoDir"
            & git clone --quiet --branch $Branch $RepoUrl $RepoDir
        } else {
            Write-Host "    Cloning $RepoUrl (default branch) to $RepoDir"
            & git clone --quiet $RepoUrl $RepoDir
        }
        if ($LASTEXITCODE -ne 0) { Fail "git clone of $RepoUrl failed." }
    }
    Write-Host "    At $(git -C $RepoDir log -1 --format='%h %s')"

    # Carry on with the checkout's copy of this script, so the run always matches the repo it configures from.
    $again = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $RepoDir 'setup-obs-windows.ps1'), '-FromCheckout')
    foreach ($p in 'Config', 'AudioDevice', 'PtzInstaller', 'DskRepo') {
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
    # DistroAV finds NDI through NDI_RUNTIME_DIR_V6 (or V5), which the NDI 6 Runtime and NDI Tools installers set;
    # NDILIB_REDIST_FOLDER is the older name. The runtime's own folder is checked too, in case the variable is
    # only set after a restart.
    $dirs = @('NDI_RUNTIME_DIR_V6', 'NDI_RUNTIME_DIR_V5', 'NDILIB_REDIST_FOLDER' | ForEach-Object {
        [Environment]::GetEnvironmentVariable($_, 'Machine')
    }) + @(Join-Path $env:ProgramFiles 'NDI\NDI 6 Runtime\v6')
    foreach ($dir in $dirs) {
        if ($dir -and (Test-Path (Join-Path $dir 'Processing.NDI.Lib.x64.dll'))) { return $true }
    }
    return $false
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

# Returns $false instead of failing when -NoFail is given and the repo has no matching installer.
function Install-FromGitHub($repo, $pattern, $label, [switch]$IncludePrerelease, [switch]$NoFail) {
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
            return $true
        }
    }
    if ($NoFail) { return $false }
    Fail "No $label Windows installer found in $repo releases."
}

Step '[4/7] DistroAV (NDI), Downstream Keyer and obs-ptz (PTZ Controls)'
$null = Install-FromGitHub 'DistroAV/DistroAV' 'distroav-*-windows-x64-Installer.exe' 'DistroAV'
# Downstream Keyer from $DskRepo, the fork that adds Load On Scene; its releases are betas so far. Matches both
# exeldro's downstream-keyer-X-windows-installer.exe and the fork's downstream-keyer-X-windows-x64-Installer.exe.
$dskPattern = 'downstream-keyer-*-windows*installer.exe'
# Fall back to exeldro's release (the Windows equivalent of Flathub's on Ubuntu) whenever the fork can't be used:
# no installer published, or the fork can't be reached or downloaded from.
$dskFromFork = $false
try {
    $dskFromFork = Install-FromGitHub $DskRepo $dskPattern 'Downstream Keyer' -IncludePrerelease -NoFail
    if (-not $dskFromFork) { Write-Warning "No Downstream Keyer installer is published in $DskRepo; installing exeldro's release instead." }
} catch {
    Write-Warning "Could not get Downstream Keyer from $DskRepo ($($_.Exception.Message)); installing exeldro's release instead."
}
if (-not $dskFromFork) {
    $null = Install-FromGitHub 'exeldro/obs-downstream-keyer' $dskPattern 'Downstream Keyer'
}
if ($PtzInstaller) {
    if (-not (Test-Path $PtzInstaller)) { Fail "No such file: $PtzInstaller" }
    Install-Exe $PtzInstaller
} else {
    # Upstream only publishes pre-releases (1.0 betas) so far; take the newest. It uses the same preset
    # format (camera:N, device_uuid) as the configs here.
    $null = Install-FromGitHub 'glikely/obs-ptz' 'obs-ptz-*-windows-x64-Installer.exe' 'obs-ptz' -IncludePrerelease
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
        [pscustomobject]@{ Id = $prefix + $k.PSChildName; Name = "$desc ($iface)"; Description = $desc; Interface = $iface }
    }
}
# The virtual cable's input (what OBS monitors into). Older VB-CABLE versions call it "CABLE Input"; newer ones list
# it as "Speakers (VB-Audio Virtual Cable)", next to a 16-channel "CABLE In 16 Ch", which isn't the one to use.
function Find-CableInput {
    Get-AudioEndpoints 'Render' |
        Where-Object { ($_.Description -like 'CABLE Input*' -or $_.Interface -like 'VB-Audio Virtual Cable*') -and $_.Description -notlike '*16 Ch*' } |
        Sort-Object { $_.Description -notlike 'CABLE Input*' } | Select-Object -First 1
}

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

$configRoot = Join-Path $ScriptDir 'obs-configuration'
$found = @()
if (Test-Path $configRoot) { $found = @(Get-ChildItem $configRoot -Directory | ForEach-Object Name) }
# Menu order: the Sacrament collections (Alkire and Quail, Independence), then the Stake Meeting ones (same order), then Control, then anything else.
$configs = @(@('sacrament-alkire-and-quail', 'sacrament-independence', 'stake-meeting-alkire-and-quail', 'stake-meeting-independence', 'stake-meeting-independence-control') | Where-Object { $found -contains $_ }) +
           @($found | Where-Object { @('sacrament-alkire-and-quail', 'sacrament-independence', 'stake-meeting-alkire-and-quail', 'stake-meeting-independence', 'stake-meeting-independence-control') -notcontains $_ })
# Every scene collection in obs-configuration\ is installed; $Config is the one OBS opens on. $InstallCollections is
# false only with -NoConfig (or nothing to install); $Config empty otherwise means "leave the default as it is".
$InstallCollections = -not $NoConfig -and $configs.Count -gt 0
if ($NoConfig) {
    $Config = $null
} elseif ($Config) {
    if ($configs -notcontains $Config) { Fail "No such configuration: $Config (have: $($configs -join ', '))" }
} elseif ($InstallCollections) {
    # Which collection OBS opens on: asked every time, with the one OBS was using marked; Enter keeps it.
    $userIni = Join-Path $env:APPDATA 'obs-studio\user.ini'
    $currentFile = if (Test-Path $userIni) {
        Get-Content $userIni | Where-Object { $_ -like 'SceneCollectionFile=*' } | Select-Object -First 1 | ForEach-Object { $_.Substring(20) }
    }
    $current = ''
    if ($currentFile -and ($configs -contains [IO.Path]::GetFileNameWithoutExtension($currentFile))) {
        $current = [IO.Path]::GetFileNameWithoutExtension($currentFile)
    }
    if ([Environment]::UserInteractive) {
        Write-Host 'All the scene collections are installed. Which one should OBS open on?'
        for ($i = 0; $i -lt $configs.Count; $i++) {
            $mark = if ($configs[$i] -eq $current) { '   (current)' } else { '' }
            Write-Host "  $($i + 1)) $($configs[$i])$mark"
        }
        $prompt = if ($current) { "Number (Enter keeps $current)" } else { 'Number' }
        while ($true) {
            $n = Read-Host $prompt
            if (-not $n -and $current) { Write-Host "    Keeping $current."; break }
            if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $configs.Count) { $Config = $configs[[int]$n - 1]; break }
        }
    } elseif ($current) {
        Write-Host "    Keeping the scene collection OBS was using ($currentFile). Use -Config NAME to change it."
    } else {
        Write-Host '    No -Config given and nothing to ask; installing the scene collections without changing which one OBS opens on.'
    }
}

$ObsDir = Join-Path $env:APPDATA 'obs-studio'
$docs = [Environment]::GetFolderPath('MyDocuments')
$MusicDir = Join-Path $docs 'sacrament'
New-Item -ItemType Directory -Force $MusicDir | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false

if ($InstallCollections) {
    # The microphone: the "USB Audio" source is a PulseAudio input in the repo; on Windows it is a WASAPI input.
    $inputs = @(Get-AudioEndpoints 'Capture' | Where-Object { $_.Description -notlike 'CABLE Output*' -and $_.Interface -notlike 'VB-Audio Virtual Cable*' })
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

    # The notch filters on "USB Audio" (HumNotch, SquealNotch, Notch6381, Notch13623) are VST 2.x plugins. The
    # Windows builds are in the repo (tools\hum-notch-vst\windows, built by build-windows.ps1); they go to
    # C:\Program Files\VSTPlugins, a folder OBS's VST filter lists, and the filters point there.
    $VstDir = Join-Path $env:ProgramFiles 'VSTPlugins'
    $vstBuilt = @(Get-ChildItem (Join-Path $ScriptDir 'tools\hum-notch-vst\windows') -Filter *.dll -ErrorAction SilentlyContinue)
    if ($vstBuilt.Count -gt 0) {
        New-Item -ItemType Directory -Force $VstDir | Out-Null
        try {
            $vstBuilt | Copy-Item -Destination $VstDir -Force
            Write-Host "    Notch filter plugins in ${VstDir}: $(($vstBuilt | ForEach-Object BaseName) -join ', ')"
        } catch {
            Write-Warning "Could not copy the notch filter plugins to $VstDir (is OBS open?): $($_.Exception.Message)"
        }
    } else {
        Write-Warning 'No notch filter plugins in tools\hum-notch-vst\windows; the filters on "USB Audio" will not load.'
    }

    $scenes = Join-Path $ObsDir 'basic\scenes'
    New-Item -ItemType Directory -Force $scenes | Out-Null
    # OBS accepts forward slashes in paths, and they need no JSON escaping
    $sacramentFwd = $MusicDir -replace '\\', '/'
    $vstFwd = $VstDir -replace '\\', '/'
    foreach ($f in $configs | ForEach-Object { Get-ChildItem (Join-Path $configRoot $_) -Filter *.json }) {
        $dest = Join-Path $scenes $f.Name
        if (Test-Path $dest) { Copy-Item $dest "$dest.$(Get-Date -Format yyyyMMdd-HHmmss).bak" }
        $text = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
        # Documents may be redirected to OneDrive here; the DejaVu Serif font is Linux-only, so use Georgia
        $text = $text.Replace('@HOME@/Documents/sacrament', $sacramentFwd).Replace('DejaVu Serif', 'Georgia')
        $text = $text.Replace('"id": "pulse_input_capture"', '"id": "wasapi_input_capture"')
        $text = $text.Replace('"versioned_id": "pulse_input_capture"', '"versioned_id": "wasapi_input_capture"')
        # Video capture devices (the ATEM Mini) are V4L2 inputs in the repo; on Windows they are DirectShow inputs.
        $text = $text.Replace('"id": "v4l2_input"', '"id": "dshow_input"')
        $text = $text.Replace('"versioned_id": "v4l2_input"', '"versioned_id": "dshow_input"')
        # The notch filters load ~/.vst/<name>.so on Linux; on Windows, <name>.dll from C:\Program Files\VSTPlugins.
        $text = [regex]::Replace($text, '@HOME@/\.vst/([^"/]+)\.so', ($vstFwd + '/$1.dll'))
        $text = $text.Replace('@AUDIO_DEVICE@', $deviceId)
        [IO.File]::WriteAllText($dest, $text, $utf8)
    }
    Write-Host "    Installed the scene collections: $($configs -join ', ')."
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

$profiles = @(Get-ChildItem (Join-Path $ObsDir 'basic\profiles') -Directory -ErrorAction SilentlyContinue)
if ($profiles.Count -eq 0) {
    # OBS has never run: make a "Church" profile and select it
    $profiles = @([pscustomobject]@{ FullName = (Join-Path $ObsDir 'basic\profiles\Church'); Name = 'Church' })
    Set-IniValues (Join-Path $ObsDir 'user.ini') 'Basic' @{ Profile = 'Church'; ProfileDir = 'Church' }
    Set-IniValues (Join-Path $profiles[0].FullName 'basic.ini') 'General' @{ Name = 'Church' }
}

# Video, on a first setup only, and skip OBS's Auto-Configuration Wizard.
& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'tools\set-obs-video.ps1') -ObsDir $ObsDir -IfFirstSetup
if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not set the OBS video; see tools\set-obs-video.ps1' }

# OBS's audio monitoring into the virtual cable, which Zoom hears as its microphone (the update script does the same).
& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'tools\set-obs-monitor.ps1') -ObsDir $ObsDir
if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not set the OBS monitoring device; see tools\set-obs-monitor.ps1' }

# Remote control: OBS's WebSocket server on port 4455, as on Ubuntu, so this computer can stand in as the main OBS
# for the Stake Meeting control laptop. Password from $env:OBS_WEBSOCKET_PASSWORD, else the same default as Ubuntu.
$wsPassword = if ($env:OBS_WEBSOCKET_PASSWORD) { $env:OBS_WEBSOCKET_PASSWORD } else { '2ne2-14' }
& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'tools\set-obs-websocket.ps1') -ObsDir $ObsDir -Password $wsPassword
if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not turn on the OBS WebSocket server; see tools\set-obs-websocket.ps1' }


# The window layout, with the PTZ Controls dock in place.
# and studio mode on.
& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'tools\set-obs-docks.ps1') -ObsDir $ObsDir
if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not install the OBS layout; see tools\set-obs-docks.ps1' }

# Open OBS on the chosen default scene collection.
if ($InstallCollections -and $Config) {
    $collection = Get-ChildItem (Join-Path $configRoot $Config) -Filter *.json | Select-Object -First 1
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'tools\set-obs-collection.ps1') -ObsDir $ObsDir -Collection $collection.FullName
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not set the default scene collection; see tools\set-obs-collection.ps1' }
}

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
