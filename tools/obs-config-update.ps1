<#
  Update the OBS scene collections and the OBS configuration on this computer from this repo, the same way
  setup-obs-windows.ps1 installs them, without running the rest of the setup (no software installs, no
  administrator, and the video settings are left alone). The Ubuntu twin is tools/obs-config-update.py.

    powershell -ExecutionPolicy Bypass -File .\tools\obs-config-update.ps1 [-Default FOLDER]   (FOLDER: a collection folder in obs-configuration, e.g. sacrament-independence)

  - Installs every collection in obs-configuration\ (from the branch that is checked out).
  - Each file it replaces is saved next to it as *.bak.
  - Keeps what was already picked in OBS, by source name: the "USB Audio" microphone, capture devices and
    NDI senders. A new "USB Audio" gets the input the setup script would pick (Sound Blaster, else USB, ...).
  - Puts back the OBS window layout (obs-configuration\obs-layout.ini) and turns studio mode on, every time
    (tools\set-obs-docks.ps1).
  - Points OBS's audio monitoring at the virtual cable that Zoom listens to (tools\set-obs-monitor.ps1) and
    turns on the WebSocket server, keeping its password (tools\set-obs-websocket.ps1).
  - Installs the notch filter plugins to C:\Program Files\VSTPlugins when they are missing or out of date
    (that needs administrator; otherwise it prints the command to do it).
  - Asks which collection OBS opens on (the same menu as the setup script), with the current one marked; Enter keeps
    it. -Default answers up front. Run without a console to ask in, it leaves OBS's current one.
  Run it as the person who uses OBS (no administrator needed). Close OBS first.
#>
param([string]$Default, [string]$Repo = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
if (Get-Process obs64 -ErrorAction SilentlyContinue) { Write-Host 'Close OBS first, then run this again.' -ForegroundColor Red; exit 1 }
$configRoot = Join-Path $Repo 'obs-configuration'
if (-not (Test-Path $configRoot)) { Write-Host "No obs-configuration folder in $Repo" -ForegroundColor Red; exit 1 }
Write-Host "Scene collections from $configRoot"

# Which collection OBS opens on: the same menu, in the same order, as setup-obs-windows.ps1.
$found = @(Get-ChildItem $configRoot -Directory | ForEach-Object Name)
$configs = @(@('sacrament-alkire-and-quail', 'sacrament-independence', 'stake-meeting-alkire-and-quail', 'stake-meeting-independence', 'stake-meeting-independence-control') | Where-Object { $found -contains $_ }) +
           @($found | Where-Object { @('sacrament-alkire-and-quail', 'sacrament-independence', 'stake-meeting-alkire-and-quail', 'stake-meeting-independence', 'stake-meeting-independence-control') -notcontains $_ })
# Which collection OBS opens on: asked every time, with the one OBS was using marked; Enter keeps it.
$userIni = Join-Path $env:APPDATA 'obs-studio\user.ini'
$currentFile = if (Test-Path $userIni) {
    Get-Content $userIni | Where-Object { $_ -like 'SceneCollectionFile=*' } | Select-Object -First 1 | ForEach-Object { $_.Substring(20) }
}
$current = ''
if ($currentFile -and ($configs -contains [IO.Path]::GetFileNameWithoutExtension($currentFile))) {
    $current = [IO.Path]::GetFileNameWithoutExtension($currentFile)
}
if ($Default) {
    if ($configs -notcontains $Default) { Write-Host "No collection named $Default (have: $($configs -join ', '))" -ForegroundColor Red; exit 1 }
} elseif ([Environment]::UserInteractive -and $configs.Count -gt 0) {
    Write-Host 'Which scene collection should OBS open on?'
    for ($i = 0; $i -lt $configs.Count; $i++) {
        $mark = if ($configs[$i] -eq $current) { '   (current)' } else { '' }
        Write-Host "  $($i + 1)) $($configs[$i])$mark"
    }
    $prompt = if ($current) { "Number (Enter keeps $current)" } else { 'Number' }
    while ($true) {
        $n = Read-Host $prompt
        if (-not $n -and $current) { Write-Host "Keeping $current."; break }
        if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $configs.Count) { $Default = $configs[[int]$n - 1]; break }
    }
} elseif ($current) {
    Write-Host "Keeping the scene collection OBS was using ($currentFile). Use -Default NAME to change it."
}

# The microphone, chosen the way setup-obs-windows.ps1 does it.
$MMDev = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture'
$inputs = foreach ($k in Get-ChildItem $MMDev -ErrorAction SilentlyContinue) {
    if ((Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).DeviceState -ne 1) { continue }
    $p = Get-ItemProperty (Join-Path $k.PSPath 'Properties') -ErrorAction SilentlyContinue
    if (-not $p) { continue }
    $desc = $p.'{a45c254e-df1c-4efd-8020-67d146a850e0},2'
    [pscustomobject]@{ Id = '{0.0.1.00000000}.' + $k.PSChildName; Name = "$desc ($($p.'{b3f8fa53-0004-438e-9003-51a46e139bfc},6'))"; Description = $desc }
}
$real = @($inputs | Where-Object { $_.Description -notlike 'CABLE Output*' -and $_.Name -notmatch 'NDI' })
$pick = $real | Where-Object Name -match 'Sound Blaster' | Select-Object -First 1
if (-not $pick) { $pick = $real | Where-Object Name -match 'USB' | Select-Object -First 1 }
if (-not $pick) { $pick = $real | Select-Object -First 1 }
$deviceId = if ($pick) { $pick.Id } else { 'default' }

$ObsDir = Join-Path $env:APPDATA 'obs-studio'
$scenes = Join-Path $ObsDir 'basic\scenes'
New-Item -ItemType Directory -Force $scenes | Out-Null
$sacramentFwd = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'sacrament') -replace '\\', '/'
$utf8 = New-Object System.Text.UTF8Encoding $false

# The notch filter plugins (the filters on "USB Audio"), as setup-obs-windows.ps1 installs them: from
# tools\hum-notch-vst\windows to C:\Program Files\VSTPlugins. Writing there needs administrator, so when this
# runs without it and a plugin is missing or out of date, it says how to copy them instead.
$VstDir = Join-Path $env:ProgramFiles 'VSTPlugins'
$vstFwd = $VstDir -replace '\\', '/'
$vstStale = @(Get-ChildItem (Join-Path $Repo 'tools\hum-notch-vst\windows') -Filter *.dll -ErrorAction SilentlyContinue | Where-Object {
    $installed = Join-Path $VstDir $_.Name
    -not (Test-Path $installed) -or (Get-FileHash $installed).Hash -ne (Get-FileHash $_.FullName).Hash
})
if ($vstStale.Count -gt 0) {
    try {
        New-Item -ItemType Directory -Force $VstDir -ErrorAction Stop | Out-Null
        $vstStale | Copy-Item -Destination $VstDir -Force -ErrorAction Stop
        Write-Host "Notch filter plugins installed in ${VstDir}: $(($vstStale | ForEach-Object BaseName) -join ', ')"
    } catch {
        $src = Join-Path $Repo 'tools\hum-notch-vst\windows\*.dll'
        Write-Host "The notch filter plugins need installing ($(($vstStale | ForEach-Object BaseName) -join ', ')), which needs administrator." -ForegroundColor Yellow
        Write-Host "  In PowerShell as administrator: New-Item -ItemType Directory -Force '$VstDir'; Copy-Item '$src' '$VstDir' -Force" -ForegroundColor Yellow
    }
}

foreach ($f in $configs | ForEach-Object { Get-ChildItem (Join-Path $configRoot $_) -Filter *.json }) {
    $dest = Join-Path $scenes $f.Name
    $text = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    $text = $text.Replace('@HOME@/Documents/sacrament', $sacramentFwd).Replace('DejaVu Serif', 'Georgia')
    $text = $text.Replace('"id": "pulse_input_capture"', '"id": "wasapi_input_capture"').Replace('"versioned_id": "pulse_input_capture"', '"versioned_id": "wasapi_input_capture"')
    $text = $text.Replace('"id": "v4l2_input"', '"id": "dshow_input"').Replace('"versioned_id": "v4l2_input"', '"versioned_id": "dshow_input"')
    $text = [regex]::Replace($text, '@HOME@/\.vst/([^"/]+)\.so', ($vstFwd + '/$1.dll'))

    # Keep what was picked in OBS: the microphone, capture devices and NDI senders, by source name.
    $mic = $deviceId; $kept = @()
    if (Test-Path $dest) {
        $old = [IO.File]::ReadAllText($dest, [Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($s in $old.sources) {
            $n = [regex]::Escape($s.name)
            if ($s.id -eq 'wasapi_input_capture' -and $s.name -eq 'USB Audio' -and $s.settings.device_id) { $mic = $s.settings.device_id; $kept += 'USB Audio' }
            if ($s.id -eq 'dshow_input' -and $s.settings.video_device_id) {
                $re = "(`"name`": `"$n`",[^{]*?`"settings`": \{[^}]*?)`"video_device_id`": `"`""
                $v = $s.settings.video_device_id.Replace('\', '\\')
                if ([regex]::IsMatch($text, $re)) { $text = [regex]::Replace($text, $re, { param($m) $m.Groups[1].Value + "`"video_device_id`": `"$v`"" }); $kept += $s.name }
            }
            if ($s.id -eq 'ndi_source' -and $s.settings.ndi_source_name) {
                $re = "(`"name`": `"$n`",[^{]*?`"settings`": \{[^}]*?)`"ndi_source_name`": `"[^`"]*`""
                $v = $s.settings.ndi_source_name
                if ([regex]::IsMatch($text, $re)) { $text = [regex]::Replace($text, $re, { param($m) $m.Groups[1].Value + "`"ndi_source_name`": `"$v`"" }); $kept += $s.name }
            }
        }
        Copy-Item $dest "$dest.$(Get-Date -Format yyyyMMdd-HHmmss).bak"
    }
    $text = $text.Replace('@AUDIO_DEVICE@', $mic)
    $null = $text | ConvertFrom-Json   # stop before writing a broken file
    [IO.File]::WriteAllText($dest, $text, $utf8)
    Write-Host "Updated $($f.Name) ($(($text | ConvertFrom-Json).name))"
    if ($kept) { Write-Host "    kept from OBS: $($kept -join ', ')" }
}

# The window layout and studio mode on, put back every time, as the setup script does.
& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'tools\set-obs-docks.ps1') -ObsDir $ObsDir
if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not install the OBS layout; see tools\set-obs-docks.ps1' }
# OBS's audio monitoring into the virtual cable, which Zoom hears as its microphone, as the setup script does.
& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'tools\set-obs-monitor.ps1') -ObsDir $ObsDir
if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not set the OBS monitoring device; see tools\set-obs-monitor.ps1' }
# The WebSocket server for remote control, keeping this computer's current password (as the Ubuntu update does).
$env:OBS_WEBSOCKET_PASSWORD = $null
& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'tools\set-obs-websocket.ps1') -ObsDir $ObsDir
if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not turn on the OBS WebSocket server; see tools\set-obs-websocket.ps1' }

if ($Default) {
    $c = Get-ChildItem (Join-Path $configRoot $Default) -Filter *.json | Select-Object -First 1
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'tools\set-obs-collection.ps1') -ObsDir $ObsDir -Collection $c.FullName
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not set the default scene collection; see tools\set-obs-collection.ps1' }
}
