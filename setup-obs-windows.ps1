<#
.SYNOPSIS
  Install OBS Studio on Windows with the plugins this setup needs (Windows twin of setup-obs-flatpak.sh).

.DESCRIPTION
  - OBS Studio (via winget): installs it, or upgrades it when the installed one is older than 33.0
  - NDI Runtime 6.3+ (via winget); on Windows it already decodes HX2/HX3 cameras
  - DistroAV (NDI plugin) and obs-ptz (PTZ Controls), latest releases from GitHub
  - lets OBS through the Windows firewall (NDI discovery and video)
  - the building's OBS scene collection from configs\<name>\
  - the sacrament graphic and music in Documents\sacrament

  Run from an elevated PowerShell (Run as administrator):
    powershell -ExecutionPolicy Bypass -File .\setup-obs-windows.ps1 [-Config quail-config | -NoConfig]

.PARAMETER Config      Install the OBS scenes and camera setup in configs\<name> (asks if omitted).
.PARAMETER NoConfig    Skip the OBS configuration.
.PARAMETER PtzInstaller  Use this obs-ptz installer .exe instead of the latest glikely/obs-ptz release.
#>
param(
    [string]$Config,
    [switch]$NoConfig,
    [string]$PtzInstaller
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # makes Invoke-WebRequest much faster
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# DistroAV 6.2.2 installs to the OBS 33+ plugin location, and obs-ptz needs 32+; require 33.
$MinObs = [version]'33.0.0'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ObsExe = Join-Path $env:ProgramFiles 'obs-studio\bin\64bit\obs64.exe'

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Fail 'Please run this from an elevated PowerShell (right-click, Run as administrator).' }
if (Get-Process obs64 -ErrorAction SilentlyContinue) { Fail 'OBS is running. Close it and run this again.' }
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Fail 'winget was not found. Install "App Installer" from the Microsoft Store (or update Windows) and retry.'
}

function Get-ObsVersion {
    if (-not (Test-Path $ObsExe)) { return $null }
    $v = (Get-Item $ObsExe).VersionInfo
    return [version]('{0}.{1}.{2}' -f $v.FileMajorPart, $v.FileMinorPart, $v.FileBuildPart)
}

function Winget-Run($wingetArgs) {
    & winget @wingetArgs --silent --accept-package-agreements --accept-source-agreements
    # -1978335189 = no applicable upgrade, -1978335135 = already installed: both fine
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189 -and $LASTEXITCODE -ne -1978335135) {
        Fail "winget $($wingetArgs -join ' ') failed (exit $LASTEXITCODE)."
    }
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

function Install-Exe($file) {
    $p = Start-Process $file -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-' -Wait -PassThru
    if ($p.ExitCode -ne 0) { Fail "$file failed (exit $($p.ExitCode))." }
}

# ---- 1. OBS Studio ---------------------------------------------------------
Step '[1/6] Checking OBS Studio'
$have = Get-ObsVersion
if ($have -and $have -ge $MinObs) {
    Write-Host "    OBS $have is new enough."
} else {
    if ($have) {
        Write-Host "    OBS $have is older than $MinObs; upgrading."
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

# ---- 2. NDI Runtime --------------------------------------------------------
Step '[2/6] Checking the NDI Runtime (needed by DistroAV)'
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

# ---- 3. Plugins ------------------------------------------------------------
Step '[3/6] Installing DistroAV (NDI)'
Install-FromGitHub 'DistroAV/DistroAV' 'distroav-*-windows-x64-Installer.exe' 'DistroAV'

Step '[4/6] Installing obs-ptz (PTZ Controls)'
if ($PtzInstaller) {
    if (-not (Test-Path $PtzInstaller)) { Fail "No such file: $PtzInstaller" }
    Install-Exe $PtzInstaller
} else {
    # the project only publishes pre-releases (1.0 betas) so far; take the newest
    Install-FromGitHub 'glikely/obs-ptz' 'obs-ptz-*-windows-x64-Installer.exe' 'obs-ptz' -IncludePrerelease
}

# ---- Firewall: NDI discovery (mDNS) and video need OBS reachable on the LAN -
Step 'Letting OBS through the Windows firewall'
if (-not (Get-NetFirewallRule -DisplayName 'OBS Studio (church setup)' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'OBS Studio (church setup)' -Direction Inbound -Action Allow `
        -Program $ObsExe -Profile Any | Out-Null
}

# ---- OBS configuration -----------------------------------------------------
Step 'Choosing the OBS configuration'
$configRoot = Join-Path $ScriptDir 'configs'
$configs = @()
if (Test-Path $configRoot) { $configs = @(Get-ChildItem $configRoot -Directory | ForEach-Object Name) }
if ($NoConfig) {
    $Config = $null
} elseif (-not $Config) {
    if ($configs.Count -eq 0 -or -not [Environment]::UserInteractive) {
        Write-Host '    No -Config given and nothing to ask; skipping the OBS configuration.'
    } else {
        Write-Host "Which building's OBS configuration should be installed?"
        for ($i = 0; $i -lt $configs.Count; $i++) { Write-Host "  $($i + 1)) $($configs[$i])" }
        Write-Host "  $($configs.Count + 1)) none (set OBS up by hand)"
        do {
            $n = Read-Host 'Number'
        } until ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $configs.Count + 1)
        if ([int]$n -le $configs.Count) { $Config = $configs[[int]$n - 1] }
    }
}

$docs = [Environment]::GetFolderPath('MyDocuments')
$MusicDir = Join-Path $docs 'sacrament'
New-Item -ItemType Directory -Force $MusicDir | Out-Null

if ($Config) {
    $src = Join-Path $configRoot $Config
    if (-not (Test-Path $src)) { Fail "No such configuration: $Config (have: $($configs -join ', '))" }
    $scenes = Join-Path $env:APPDATA 'obs-studio\basic\scenes'
    New-Item -ItemType Directory -Force $scenes | Out-Null
    # OBS accepts forward slashes in paths, and they need no JSON escaping
    $sacramentFwd = $MusicDir -replace '\\', '/'
    $utf8 = New-Object System.Text.UTF8Encoding $false
    foreach ($f in Get-ChildItem $src -Filter *.json) {
        $dest = Join-Path $scenes $f.Name
        if (Test-Path $dest) { Copy-Item $dest "$dest.$(Get-Date -Format yyyyMMdd-HHmmss).bak" }
        $text = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
        # the config points at @HOME@/Documents/sacrament (Documents may be redirected to OneDrive here);
        # it also uses the DejaVu Serif font, which Windows lacks, so use Georgia
        $text = $text.Replace('@HOME@/Documents/sacrament', $sacramentFwd).Replace('DejaVu Serif', 'Georgia')
        [IO.File]::WriteAllText($dest, $text, $utf8)
    }
    Write-Host "    Installed the '$Config' scene collection. In OBS choose it from the Scene Collection menu."
}

# ---- Sacrament graphic and music -------------------------------------------
Step '[5/6] Making the sacrament graphic'
try {
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'tools\make-sacrament-graphic.ps1') `
        -Out (Join-Path $MusicDir 'sacrament-graphic.png')
    if ($LASTEXITCODE -ne 0) { throw "exit $LASTEXITCODE" }
} catch {
    Write-Warning "Could not make the sacrament graphic ($_); see tools\make-sacrament-graphic.ps1"
}

# Piano accompaniment of "Bread of Life, Living Water" (church hymn recordings are free for home and
# church use). Not stored in the repo. Failure here is not fatal.
Step '[6/6] Downloading the sacrament music'
$MusicPage = 'https://www.churchofjesuschrist.org/media/music/songs/bread-of-life-living-water?lang=eng'
$MusicFallback = 'https://assets.churchofjesuschrist.org/a6/fa/a6fa4142ee3511eeab89eeeeac1ef623ccb828a4/bread_of_life_living_water.mp3'
$MusicFile = Join-Path $MusicDir 'bread-of-life-living-water-piano.mp3'
if (-not (Test-Path $MusicFile) -or (Get-Item $MusicFile).Length -eq 0) {
    $url = $MusicFallback
    try {
        $html = (Invoke-WebRequest $MusicPage -UserAgent 'Mozilla/5.0' -UseBasicParsing).Content
        # the page lists each recording's URL; pick the piano accompaniment (not guitar/vocal)
        if ($html -match '"assetType":"AUDIO_ACCOMPANIMENT","distributionUrl":"([^"]+\.mp3)"') { $url = $Matches[1] }
    } catch { }
    try {
        Invoke-WebRequest $url -OutFile "$MusicFile.part" -UserAgent 'Mozilla/5.0' -UseBasicParsing
        Move-Item "$MusicFile.part" $MusicFile -Force
    } catch {
        Remove-Item "$MusicFile.part" -ErrorAction SilentlyContinue
        Write-Warning "Could not download the sacrament music; fetch it by hand from $MusicPage"
    }
}

Write-Host '==> Done. Start OBS from the Start menu.' -ForegroundColor Green
