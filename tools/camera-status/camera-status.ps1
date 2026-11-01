# Ask each PTZ camera whether it is powered on, then offer to turn them all on or put them in standby
# (Windows twin of camera-status.py).
#
# Sends each camera the VISCA power inquiry (81 09 04 00 FF) over TCP and prints ON or STANDBY. The
# cameras are the ones in cameras.json, next to this script, or the ones given with -CameraHost.
# OBS and its scene collections are not used. When only the first camera (192.168.111.245)
# answers, the church has one camera: it is shown as "PTZ Camera". Otherwise each camera that
# answers is shown by its name, PTZ Left and PTZ Right, and each one that does not as "Error: PTZ
# Left not found". A menu then asks whether to change nothing, set every camera on, or set every
# camera to standby; only the cameras found are changed. -Set On or -Set Standby does that without
# the menu. With no answer to read (input that has run out), the menu changes nothing.
#
# Exit status: 0 when every camera answered (or the one camera of a single-camera church did), 1
# when any was not found or gave no answer.
param(
    # HOST or HOST:PORT; more than one can be given, separated by commas
    [string[]]$CameraHost,
    [string]$Cameras,
    [double]$Timeout = 3,
    [ValidateSet('On', 'Standby')][string]$Set
)
$ErrorActionPreference = 'Stop'
if (-not $Cameras) { $Cameras = Join-Path $PSScriptRoot 'cameras.json' }

$DefaultPort = 5678
$PowerInq = [byte[]](0x81, 0x09, 0x04, 0x00, 0xFF)
$PowerStates = @{ 2 = 'ON'; 3 = 'STANDBY'; 4 = 'POWER ERROR' }
$On = 2; $Standby = 3
$PowerSet = @{  # the command that puts the camera in each state
    $On = [byte[]](0x81, 0x01, 0x04, 0x00, 0x02, 0xFF)
    $Standby = [byte[]](0x81, 0x01, 0x04, 0x00, 0x03, 0xFF)
}
$Actions = @{ $On = 'turned on'; $Standby = 'put in standby' }
$Targets = @{ 'On' = $On; 'Standby' = $Standby }
$Menu = @(@('No change', ''), @('Set on', 'On'), @('Set standby', 'Standby'))
$SingleName = 'PTZ Camera'  # the camera's name when it is the only one that answers

# Name, host and port of each camera in cameras.json
function Get-Cameras($path) {
    $data = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($c in @($data)) {
        $port = if ($c.port) { [int]$c.port } else { $DefaultPort }
        $name = if ($c.name) { $c.name } else { $c.host }
        [pscustomobject]@{ Source = $name; Host = $c.host; Port = $port }
    }
}

# Name, host and port for a -CameraHost of HOST or HOST:PORT
function Get-HostCamera($text) {
    $h, $p = $text -split ':', 2
    $port = if ($p) { [int]$p } else { $DefaultPort }
    [pscustomobject]@{ Source = $h; Host = $h; Port = $port }
}

# The camera's next reply: one VISCA packet, ending in FF
function Read-Packet($stream) {
    $packet = New-Object Collections.Generic.List[byte]
    while ($true) {
        try { $b = $stream.ReadByte() } catch { throw [TimeoutException]'timed out waiting for an answer' }
        if ($b -lt 0) { throw 'the camera closed the connection' }
        $packet.Add([byte]$b)
        if ($b -eq 0xFF) { break }
    }
    $p = $packet.ToArray()
    if ($p.Length -ge 3 -and ($p[1] -band 0xF0) -eq 0x60) {  # y0 6z ee FF: an error
        throw ('the camera answered with VISCA error ' + (($p | ForEach-Object { $_.ToString('x2') }) -join ' '))
    }
    return , $p
}

# The camera's answer to the power inquiry, and what was done about it. $change is '' to only ask,
# or 'On' or 'Standby' to put the camera in that state whatever it was in.
function Get-PowerState($cameraHost, $port, $change) {
    $ms = [int]($Timeout * 1000)
    $client = New-Object Net.Sockets.TcpClient
    try {
        if (-not $client.ConnectAsync($cameraHost, $port).Wait($ms)) { throw 'timed out connecting' }
        $stream = $client.GetStream()
        $stream.ReadTimeout = $ms
        $stream.Write($PowerInq, 0, $PowerInq.Length)
        do { $p = Read-Packet $stream } until ($p.Length -eq 4 -and $p[1] -eq 0x50)  # y0 50 0p FF: the answer
        $code = [int]$p[2]
        $state = if ($PowerStates.ContainsKey($code)) { $PowerStates[$code] }
                 else { 'UNKNOWN (' + (($p | ForEach-Object { $_.ToString('x2') }) -join ' ') + ')' }
        if (-not $change) { return $state }
        $target = $Targets[$change]
        $cmd = $PowerSet[$target]
        $stream.Write($cmd, 0, $cmd.Length)
        $action = $Actions[$target]
        if ($code -eq $target) { $action += ' (it already was)' }
        # y0 4z FF says the camera took the command, y0 5z FF that it has carried it out. A camera
        # can take a while to power up, so a command it took but has not finished still counts.
        $accepted = $false
        try {
            while ($true) {
                $p = Read-Packet $stream
                if ($p.Length -eq 3 -and ($p[1] -band 0xF0) -eq 0x40) { $accepted = $true }
                elseif ($p.Length -eq 3 -and ($p[1] -band 0xF0) -eq 0x50) { return "$state, $action" }
            }
        } catch [TimeoutException] {
            if (-not $accepted) { throw }
        }
        return "$state, $action (still finishing)"
    } finally {
        $client.Close()
    }
}

# What each camera said, and whether it answered
function Get-Results($found, $change) {
    foreach ($cam in $found) {
        try {
            $state = Get-PowerState $cam.Host $cam.Port $change
            [pscustomobject]@{ Camera = $cam; State = $state; Answered = $true }
        } catch {
            $msg = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
            [pscustomobject]@{ Camera = $cam; State = "NO ANSWER ($msg)"; Answered = $false }
        }
    }
}

function Show-Results($results) {
    foreach ($r in $results) {
        Write-Host ("  {0} ({1}:{2}): {3}" -f $r.Camera.Source, $r.Camera.Host, $r.Camera.Port, $r.State)
    }
}

# Print each camera's power state, and what was done about it; $true if every camera answered
function Show-Report($found, $change) {
    $results = @(Get-Results $found $change)
    Show-Results $results
    return -not ($results | Where-Object { -not $_.Answered })
}

# A church with one camera has it at the first address: when that is the only one to answer, it is
# named PTZ Camera. Any other camera that is the only one to answer keeps its name, PTZ Right, and
# the first one is reported missing.
function Select-Single($results) {
    $answered = @($results | Where-Object Answered)
    if ($answered.Count -ne 1 -or $answered[0] -ne $results[0]) { return $null }
    $cam = $answered[0].Camera
    $single = [pscustomobject]@{ Source = $SingleName; Host = $cam.Host; Port = $cam.Port }
    return [pscustomobject]@{ Camera = $single; State = $answered[0].State; Answered = $true }
}

function Show-Missing($missing) {
    foreach ($cam in $missing) { Write-Host "  Error: $($cam.Source) not found" }
}

# The change picked from the menu: '' for no change, 'On', or 'Standby'
function Read-Menu {
    Write-Host ''
    for ($i = 0; $i -lt $Menu.Count; $i++) { Write-Host ("  {0}. {1}" -f ($i + 1), $Menu[$i][0]) }
    while ($true) {
        Write-Host -NoNewline "Choose 1-$($Menu.Count): "
        $choice = [Console]::In.ReadLine()
        if ($null -eq $choice) { Write-Host ''; return '' }
        $n = 0
        if ([int]::TryParse($choice.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $Menu.Count) { return $Menu[$n - 1][1] }
        Write-Host "Enter a number from 1 to $($Menu.Count)."
    }
}

if ($CameraHost) {
    $found = @($CameraHost | ForEach-Object { Get-HostCamera $_ })
} else {
    $found = @(Get-Cameras $Cameras)
    Write-Host "Cameras from $Cameras"
}

$results = @(Get-Results $found '')
$single = Select-Single $results
if ($single) {
    $answered = @($single); $missing = @()
} else {
    $answered = @($results | Where-Object Answered)
    $missing = @($results | Where-Object { -not $_.Answered } | ForEach-Object { $_.Camera })
}
if ($answered.Count -eq 0) {  # no camera to show or change
    Show-Results $results
    exit 1
}
$cams = @($answered | ForEach-Object { $_.Camera })
if ($Set) {
    $ok = Show-Report $cams $Set
    Show-Missing $missing
    if ($ok -and $missing.Count -eq 0) { exit 0 } else { exit 1 }
}
Show-Results $answered
Show-Missing $missing
$change = Read-Menu
if (-not $change) {
    if ($missing.Count -eq 0) { exit 0 } else { exit 1 }
}
Write-Host ''
$ok = Show-Report $cams $change
Show-Missing $missing
if ($ok -and $missing.Count -eq 0) { exit 0 } else { exit 1 }
