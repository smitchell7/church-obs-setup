# Ask each PTZ camera whether it is powered on (Windows twin of camera-status.py).
#
# Sends each camera the VISCA power inquiry (81 09 04 00 FF) over TCP and prints ON or STANDBY. The
# cameras are the single or dual set in cameras.json, next to this script, or the ones given with
# -CameraHost. OBS and its scene collections are not used. With -Toggle, each camera in standby is
# turned on and each one that is on is put in standby.
#
# Exit status: 0 when every camera answered, 1 when any could not be reached or gave no answer.
param(
    [Parameter(Position = 0)]
    [ValidateSet('single', 'dual', 'single-camera', 'dual-camera')][string]$Setup,
    # HOST or HOST:PORT; more than one can be given, separated by commas
    [string[]]$CameraHost,
    [string]$Cameras,
    [double]$Timeout = 3,
    [switch]$Toggle
)
$ErrorActionPreference = 'Stop'
if (-not $Cameras) { $Cameras = Join-Path $PSScriptRoot 'cameras.json' }

$DefaultPort = 5678
$PowerInq = [byte[]](0x81, 0x09, 0x04, 0x00, 0xFF)
$PowerStates = @{ 2 = 'ON'; 3 = 'STANDBY'; 4 = 'POWER ERROR' }
$PowerSet = @{  # with -Toggle: the command for each state, which switches to the other one
    3 = [byte[]](0x81, 0x01, 0x04, 0x00, 0x02, 0xFF)  # in standby: power on
    2 = [byte[]](0x81, 0x01, 0x04, 0x00, 0x03, 0xFF)  # on: standby
}

# Name, host and port of each camera of the single or dual set in cameras.json
function Get-Cameras($setupName, $path) {
    $data = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($c in @($data.$setupName)) {
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

# The camera's answer to the power inquiry, and with -Toggle, what was done about it: a camera in
# standby is turned on, and one that is on is put in standby.
function Get-PowerState($cameraHost, $port) {
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
        if (-not $Toggle -or -not $PowerSet.ContainsKey($code)) { return $state }
        $cmd = $PowerSet[$code]
        $stream.Write($cmd, 0, $cmd.Length)
        $action = if ($code -eq 3) { 'turned on' } else { 'put in standby' }
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

if ($CameraHost) {
    $found = @($CameraHost | ForEach-Object { Get-HostCamera $_ })
} elseif ($Setup) {
    $found = @(Get-Cameras ($Setup -replace '-camera$', '') $Cameras)
    Write-Host "Cameras from $Cameras"
} else {
    Write-Host 'Say which cameras to ask: single, dual, or -CameraHost.'
    exit 2
}
$ok = $true
foreach ($cam in $found) {
    try {
        $state = Get-PowerState $cam.Host $cam.Port
    } catch {
        $msg = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        $state = "NO ANSWER ($msg)"; $ok = $false
    }
    Write-Host ("  {0} ({1}:{2}): {3}" -f $cam.Source, $cam.Host, $cam.Port, $state)
}
if ($ok) { exit 0 } else { exit 1 }
