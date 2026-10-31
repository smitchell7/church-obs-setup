# Build the 1920x1080 background for the sacrament scene (Windows twin of make-sacrament-graphic.py).
#
# Downloads The Good Shepherd from churchofjesuschrist.org (personal, church-related, noncommercial
# use) unless -Image is given, crops it to 16:9 and darkens the bottom so the scene's text layers
# stay readable. The text itself is OBS text sources in the scene collection, not part of this picture.
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Image
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$PaintingUrl = 'https://www.churchofjesuschrist.org/imgs/75e126dbc032d0810fc934018c5ca415116ce5cb/full/1920,/0/default?download=true'
$W = 1920; $H = 1080

function New-Canvas {
    $bmp = New-Object System.Drawing.Bitmap $W, $H
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    return @($bmp, $g)
}

function Fit-Image($img) {
    $ratio = $img.Width / $img.Height
    $bmp, $g = New-Canvas
    if ($ratio -ge 1.4) {
        # close to widescreen: scale to the width and crop a 16:9 window near the top
        $scaledH = [math]::Round($W / $ratio)
        $top = 0
        if ($scaledH -gt $H) { $top = [math]::Min(60, $scaledH - $H) }
        $g.DrawImage($img, (New-Object System.Drawing.Rectangle 0, (-$top), $W, $scaledH))
    } else {
        # tall picture: float it over a blurred copy of itself (shrink then enlarge = cheap blur)
        $small = New-Object System.Drawing.Bitmap 48, ([math]::Max(2, [math]::Round(48 * $H / $W)))
        $sg = [System.Drawing.Graphics]::FromImage($small)
        $sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $sg.DrawImage($img, (New-Object System.Drawing.Rectangle 0, 0, $small.Width, $small.Height))
        $sg.Dispose()
        $g.DrawImage($small, (New-Object System.Drawing.Rectangle 0, 0, $W, $H))
        $small.Dispose()
        $fgW = [math]::Round($H * $ratio)
        $g.DrawImage($img, (New-Object System.Drawing.Rectangle ([math]::Floor(($W - $fgW) / 2)), 0, $fgW, $H))
    }
    $g.Dispose()
    return $bmp
}

if ($Image) {
    $src = [System.Drawing.Image]::FromFile((Resolve-Path $Image).Path)
} else {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', 'Mozilla/5.0')
    $ms = New-Object System.IO.MemoryStream(, $wc.DownloadData($PaintingUrl))
    $src = [System.Drawing.Image]::FromStream($ms)
}

$bmp = Fit-Image $src
$g = [System.Drawing.Graphics]::FromImage($bmp)
# dark gradient across the bottom third so the text stays readable
$startY = [int]($H * 0.55)
for ($y = $startY; $y -lt $H; $y++) {
    $t = ($y - $H * 0.55) / ($H * 0.45)
    $alpha = [int](215 * [math]::Pow($t, 1.3))
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($alpha, 8, 12, 20))
    $g.FillRectangle($brush, 0, $y, $W, 1)
    $brush.Dispose()
}
$g.Dispose()

$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose(); $src.Dispose()
Write-Host "Wrote $Out"
