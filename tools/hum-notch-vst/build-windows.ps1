<#
.SYNOPSIS
  Builds the Hum, Squeal and tone-notch VST 2.x plugins as Windows DLLs (the Windows twin of build.sh).

.DESCRIPTION
  Writes HumNotch.dll, SquealNotch.dll, Notch6381.dll and Notch13623.dll to tools\hum-notch-vst\windows\. Those
  built copies are committed, so the church computers need no compiler: setup-obs-windows.ps1 copies them to
  C:\Program Files\VSTPlugins\ (a folder OBS's VST 2.x filter lists) and points the "USB Audio" filters at them.

  Needs clang (winget install LLVM.LLVM) and the Visual Studio C++ build tools (for the Windows SDK and linker).
  The C runtime is linked in statically, so the DLLs need no Visual C++ redistributable.
  Run it again after changing hum_notch_vst.c or tone_notch_vst.c, and commit the new DLLs.

  The notch settings match build.sh; keep the two in step.
#>
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$out = Join-Path $here 'windows'
New-Item -ItemType Directory -Force $out | Out-Null

$clang = (Get-Command clang -ErrorAction SilentlyContinue).Source
if (-not $clang -and (Test-Path "$env:ProgramFiles\LLVM\bin\clang.exe")) { $clang = "$env:ProgramFiles\LLVM\bin\clang.exe" }
if (-not $clang) { throw 'clang not found. Install it with: winget install LLVM.LLVM' }

function Build($name, $source, [string[]]$defines) {
    $dll = Join-Path $out "$name.dll"
    # The arguments go through a response file: Windows PowerShell drops the quotes in NOTCH_NAME="..." when it
    # passes them to a program directly.
    $q = { param($s) '"' + ($s -replace '\\', '/' -replace '"', '\"') + '"' }
    $rsp = Join-Path $out "$name.rsp"
    $lines = @('-O2', '-shared', '-fms-runtime-lib=static', '-Wall', '-Wextra', '-Wno-deprecated-declarations') +
             ($defines | ForEach-Object { & $q "-D$_" }) + @('-o', (& $q $dll), (& $q (Join-Path $here $source)))
    [IO.File]::WriteAllLines($rsp, [string[]]$lines)
    & $clang "@$rsp"
    $code = $LASTEXITCODE
    Remove-Item $rsp
    if ($code -ne 0) { throw "Building $name failed." }
    # clang also leaves an import library and export file next to the DLL; only the DLL is needed.
    Remove-Item (Join-Path $out "$name.lib"), (Join-Path $out "$name.exp") -ErrorAction SilentlyContinue
    Write-Host "Built $dll"
}

Build 'HumNotch' 'hum_notch_vst.c' @()
# A steady whine near 10 kHz that drifts between about 9.8 and 10.1 kHz, so the notch is wide (Q 4, about 2.5 kHz).
Build 'SquealNotch' 'tone_notch_vst.c' @('NOTCH_HZ=10000.0', 'NOTCH_Q=4.0', 'NOTCH_NAME="Squeal Notch"', 'NOTCH_ID=0x5371754e')
# Fixed notches for two steady tones measured on the Independence Building microphone (Q 12).
Build 'Notch6381' 'tone_notch_vst.c' @('NOTCH_HZ=6381.0', 'NOTCH_Q=12.0', 'NOTCH_NAME="Notch 6381 Hz"', 'NOTCH_ID=0x4e363338')
Build 'Notch13623' 'tone_notch_vst.c' @('NOTCH_HZ=13623.0', 'NOTCH_Q=12.0', 'NOTCH_NAME="Notch 13623 Hz"', 'NOTCH_ID=0x4e313336')
