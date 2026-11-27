<#
.SYNOPSIS
  Install the OBS window layout in obs-configuration\obs-layout.ini, and open OBS in studio mode.
  (Windows twin of set-obs-docks.py.)

.DESCRIPTION
  Every run puts the layout back (docks with PTZ Controls in place, side docks, vertical mixer; not the window's position or size, which stays as each computer has it), so a
  dock closed or moved, or studio mode turned off, by accident is fixed by the next setup or update: it turns
  studio mode on every time. Also turns off OBS's popup about closing a dock. Close OBS first: it writes its own
  layout when it exits.

.PARAMETER ObsDir OBS's config folder. Default: %APPDATA%\obs-studio.
#>
param(
    [string]$ObsDir = (Join-Path $env:APPDATA 'obs-studio')
)
$ErrorActionPreference = 'Stop'

# The layout's key=value lines, from its [BasicWindow] section, in file order.
$layout = New-Object System.Collections.Specialized.OrderedDictionary
$inSection = $false
foreach ($l in Get-Content (Join-Path $PSScriptRoot '..\obs-configuration\obs-layout.ini')) {
    if ($l -match '^\s*\[(.+)\]\s*$') { $inSection = ($Matches[1] -eq 'BasicWindow') }
    elseif ($inSection -and $l -match '^([^;=\s][^=]*)=(.*)$') { $layout[$Matches[1]] = $Matches[2] }
}

$userIni = Join-Path $ObsDir 'user.ini'
$lines = if (Test-Path $userIni) { @([IO.File]::ReadAllLines($userIni)) } else { @() }

# What to set in each section. Studio mode on: OBS saves the mode on exit, so this is only the starting state;
# the next run sets it again.
$set = @{
    'General'     = [ordered]@{ WarnedAboutClosingDocks = 'true' }
    'BasicWindow' = [ordered]@{ PreviewProgramMode = 'true' }
}
foreach ($k in $layout.Keys) { $set['BasicWindow'][$k] = $layout[$k] }
# Left by an older version of this script, which installed each layout only once.
$drop = @('ChurchLayout')

# Rewrite user.ini: drop the keys being set from their sections, then add them at the top of each section.
$out = New-Object System.Collections.Generic.List[string]
$sectionName = $null
$seen = @{}
foreach ($l in $lines) {
    if ($l -match '^\s*\[(.+)\]\s*$') {
        $sectionName = $Matches[1]
        $out.Add($l)
        if ($set.Contains($sectionName)) {
            $seen[$sectionName] = $true
            foreach ($k in $set[$sectionName].Keys) { $out.Add("$k=$($set[$sectionName][$k])") }
        }
    } elseif ($sectionName -eq 'BasicWindow' -and $l -match '^([^=]+)=' -and $drop -contains $Matches[1]) {
        # dropped
    } elseif ($sectionName -and $set.Contains($sectionName) -and $l -match '^([^=]+)=' -and $set[$sectionName].Contains($Matches[1])) {
        # replaced above
    } else {
        $out.Add($l)
    }
}
foreach ($name in $set.Keys) {
    if (-not $seen[$name]) {
        $out.Add("[$name]")
        foreach ($k in $set[$name].Keys) { $out.Add("$k=$($set[$name][$k])") }
    }
}
New-Item -ItemType Directory -Force $ObsDir | Out-Null
[IO.File]::WriteAllLines($userIni, $out.ToArray(), (New-Object System.Text.UTF8Encoding $false))
Write-Host "    OBS layout (PTZ Controls docked) installed in $userIni; studio mode on"
