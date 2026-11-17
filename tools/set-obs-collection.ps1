<#
.SYNOPSIS
  Make an installed scene collection the one OBS opens with. (Windows twin of set-obs-collection.py.)

.PARAMETER Collection The collection's .json in this repo, e.g. obs-configuration\sacrament-alkire-and-quail\sacrament-alkire-and-quail.json.
.PARAMETER ObsDir     OBS's config folder. Default: %APPDATA%\obs-studio.
#>
param(
    [Parameter(Mandatory = $true)][string]$Collection,
    [string]$ObsDir = (Join-Path $env:APPDATA 'obs-studio')
)
$ErrorActionPreference = 'Stop'

$file = Get-Item $Collection
$name = ([IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json).name
$set = [ordered]@{ SceneCollection = $name; SceneCollectionFile = $file.Name }

# Rewrite user.ini: in [Basic], replace these two keys (added at the top of the section).
$ini = Join-Path $ObsDir 'user.ini'
$lines = if (Test-Path $ini) { @([IO.File]::ReadAllLines($ini)) } else { @() }
$out = New-Object System.Collections.Generic.List[string]
$inBasic = $false; $seen = $false
foreach ($l in $lines) {
    if ($l -match '^\s*\[(.+)\]\s*$') {
        $inBasic = ($Matches[1] -eq 'Basic')
        $out.Add($l)
        if ($inBasic) { $seen = $true; foreach ($k in $set.Keys) { $out.Add("$k=$($set[$k])") } }
    } elseif (-not ($inBasic -and $l -match '^([^=]+)=' -and $set.Contains($Matches[1]))) {
        $out.Add($l)
    }
}
if (-not $seen) { $out.Add('[Basic]'); foreach ($k in $set.Keys) { $out.Add("$k=$($set[$k])") } }
New-Item -ItemType Directory -Force $ObsDir | Out-Null
[IO.File]::WriteAllLines($ini, $out.ToArray(), (New-Object System.Text.UTF8Encoding $false))
Write-Host "    OBS will open with the '$name' scene collection."
