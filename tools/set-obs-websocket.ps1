<#
.SYNOPSIS
  Turn on OBS's WebSocket server (port 4455, password required) so it can be controlled remotely, e.g. by the
  Stake Meeting control laptop. (Windows twin of set-obs-websocket.py.)

.DESCRIPTION
  The password is -Password, else $env:OBS_WEBSOCKET_PASSWORD; if both are empty the existing password is kept,
  and if there is none a random one is made and printed. Close OBS first. Run again at any time.

.PARAMETER ObsDir   OBS's config folder. Default: %APPDATA%\obs-studio.
.PARAMETER Password The WebSocket password. Letters, digits and hyphens only.
#>
param(
    [string]$ObsDir = (Join-Path $env:APPDATA 'obs-studio'),
    [string]$Password = $env:OBS_WEBSOCKET_PASSWORD
)
$ErrorActionPreference = 'Stop'

$path = Join-Path $ObsDir 'plugin_config\obs-websocket\config.json'
$cfg = if (Test-Path $path) { [IO.File]::ReadAllText($path) | ConvertFrom-Json } else { New-Object psobject }

if (-not $Password) { $Password = $cfg.server_password }
$generated = -not $Password
if ($generated) {
    $bytes = New-Object byte[] 9
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $Password = [Convert]::ToBase64String($bytes).Replace('+', '-').Replace('/', '_')
}

$values = [ordered]@{
    first_load      = $false   # otherwise OBS makes its own password on first start
    server_enabled  = $true
    server_port     = 4455
    auth_required   = $true
    server_password = $Password
}
foreach ($k in $values.Keys) { $cfg | Add-Member -NotePropertyName $k -NotePropertyValue $values[$k] -Force }
if ($null -eq $cfg.alerts_enabled) { $cfg | Add-Member -NotePropertyName alerts_enabled -NotePropertyValue $false -Force }

New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
[IO.File]::WriteAllText($path, ($cfg | ConvertTo-Json) + "`n", (New-Object System.Text.UTF8Encoding $false))
Write-Host "    OBS WebSocket server enabled on port 4455 ($path)"
if ($generated) { Write-Host "    No password was given, so one was made: $Password" }
