<#
.SYNOPSIS
  Build the sacrament music playlist on Windows: one long MP3 that OBS loops on the Sacrament scene.
  (Windows twin of tools/make-sacrament-playlist.py.)

.DESCRIPTION
  OBS's media source plays a single file, so the hymns in audio\sacrament-playlist.txt are downloaded
  (piano accompaniments from churchofjesuschrist.org) and joined with ffmpeg into DIR\sacrament-playlist.mp3.
  Each hymn is kept in DIR\hymns\. Re-running downloads only what is missing and rebuilds the playlist only
  when the list or the hymns changed. A hymn that cannot be downloaded is skipped with a warning.

  powershell -ExecutionPolicy Bypass -File tools\make-sacrament-playlist.ps1 -List audio\sacrament-playlist.txt -Dir <folder> [-Ffmpeg <path>]
#>
param(
    [Parameter(Mandatory = $true)][string]$List,
    [Parameter(Mandatory = $true)][string]$Dir,
    [string]$Ffmpeg = 'ffmpeg'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Page = 'https://www.churchofjesuschrist.org/media/music/songs/{0}?lang=eng'
# The page lists every recording; the piano accompaniment is the AUDIO_ACCOMPANIMENT one.
$Mp3Re = '"assetType":"AUDIO_ACCOMPANIMENT","distributionUrl":"([^"]+\.mp3)"'

$out = Join-Path $Dir 'sacrament-playlist.mp3'
$hymnDir = Join-Path $Dir 'hymns'
New-Item -ItemType Directory -Force $hymnDir | Out-Null

$slugs = @()
foreach ($line in [IO.File]::ReadAllLines((Resolve-Path $List))) {
    $s = ($line -split '#', 2)[0].Trim()
    if ($s -and $slugs -notcontains $s) { $slugs += $s }
}

$files = @()
foreach ($slug in $slugs) {
    $dest = Join-Path $hymnDir "$slug.mp3"
    if (-not (Test-Path $dest) -or (Get-Item $dest).Length -eq 0) {
        try {
            $html = (Invoke-WebRequest ($Page -f $slug) -UserAgent 'Mozilla/5.0' -UseBasicParsing).Content
            if ($html -notmatch $Mp3Re) { throw 'no piano accompaniment listed on the page' }
            Invoke-WebRequest $Matches[1] -OutFile "$dest.part" -UserAgent 'Mozilla/5.0' -UseBasicParsing
            Move-Item "$dest.part" $dest -Force
            Write-Host "downloaded $slug"
        } catch {
            Remove-Item "$dest.part" -ErrorAction SilentlyContinue
            Write-Warning "skipping ${slug}: $_"   # one bad hymn must not lose the others
            continue
        }
    }
    $files += Get-Item $dest
}

if ($files.Count -eq 0) { Write-Host 'ERROR: no hymns available, playlist not built' -ForegroundColor Red; exit 1 }

$newest = @((Get-Item $List).LastWriteTimeUtc) + @($files | ForEach-Object LastWriteTimeUtc) | Sort-Object | Select-Object -Last 1
if ((Test-Path $out) -and (Get-Item $out).Length -gt 0 -and (Get-Item $out).LastWriteTimeUtc -ge $newest) {
    Write-Host "playlist is up to date ($($files.Count) hymns)"
    exit 0
}

# ffmpeg's concat list: forward slashes, single quotes escaped as '\''
$listing = Join-Path $env:TEMP "sacrament-concat-$PID.txt"
$lines = $files | ForEach-Object { "file '" + ($_.FullName -replace '\\', '/' -replace "'", "'\''") + "'" }
[IO.File]::WriteAllLines($listing, [string[]]$lines, (New-Object System.Text.UTF8Encoding $false))
$part = Join-Path $Dir 'sacrament-playlist.part.mp3'
try {
    # Re-encode to one format so hymns recorded differently still join cleanly.
    & $Ffmpeg -y -loglevel error -f concat -safe 0 -i $listing -vn -ac 2 -ar 44100 -c:a libmp3lame -q:a 4 $part
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed (exit $LASTEXITCODE)" }
    Move-Item $part $out -Force
} finally {
    Remove-Item $listing -ErrorAction SilentlyContinue
}
Write-Host "built $out from $($files.Count) hymns"
