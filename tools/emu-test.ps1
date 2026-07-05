# End-to-end fixture test: compile a BASIC fixture with the MEGA65-native
# compiler inside xemu, link the emitted assembly with the runtime, then run
# the compiled program and capture its screen output.
#
# Usage: powershell -File tools\emu-test.ps1 [-Fixture basic\strings.bas]
#                   [-SkipRun] [-CompileTimeout 120] [-RunWait 40]
#
# Phase 1 boots the compiler D81 and injects tools\bootstrap.bas, which
# presses RETURN (via the $D619 PETSCII injection register) to accept the
# default SOURCE.PRG and chain-loads BASIC65C. OUT.ASM appearing on the D81
# is the success signal: the compiler only renames OUT.TMP after a clean
# compile.
#
# Phase 2 writes the linked OUT.PRG back to the D81 and injects
# tools\bootstrap-run.bas, which chain-loads and runs it. The screen is
# dumped on emulator exit.
param(
    [string]$Fixture = "basic\source.bas",
    [string]$Xemu = "C:\Emulation\Mega65\xmega65.exe",
    [int]$CompileTimeout = 120,
    [int]$RunWait = 40,
    [switch]$SkipRun
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$d81 = Join-Path $repo "target\basic65c.d81"
$screenDump = Join-Path $repo "target\emu-screen.txt"
$probe = Join-Path $env:TEMP "basic65c-probe.d81"

function Stop-Xemu {
    param([System.Diagnostics.Process]$Proc, [switch]$Graceful)
    if ($Proc -and -not $Proc.HasExited) {
        if ($Graceful) {
            [void]$Proc.CloseMainWindow()
            if (-not $Proc.WaitForExit(10000)) { $Proc.Kill() }
        } else {
            $Proc.Kill()
        }
        $Proc.WaitForExit()
    }
}

Write-Host "=== build: $Fixture ==="
cmd /c ".\build.bat $Fixture"
if ($LASTEXITCODE -ne 0) { throw "build.bat failed" }

.\petcat.exe -w65 -l 2001 -o target\bootstrap.prg -- tools\bootstrap.bas
.\petcat.exe -w65 -l 2001 -o target\bootstrap-run.prg -- tools\bootstrap-run.bas

Write-Host "=== phase 1: compile $Fixture on the MEGA65 ==="
$p = Start-Process -FilePath $Xemu -ArgumentList @(
    "-8", $d81, "-hdosvirt", "true",
    "-prg", (Join-Path $repo "target\bootstrap.prg"), "-besure"
) -PassThru
$deadline = (Get-Date).AddSeconds($CompileTimeout)
$compiled = $false
Remove-Item -Force -ErrorAction SilentlyContinue target\out.asm.seq
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    Copy-Item -Force $d81 $probe
    cmd /c ".\c1541.exe -attach `"$probe`" -read `"out.asm,s`" target\out.asm.seq >nul 2>nul"
    if ((Test-Path target\out.asm.seq) -and (Get-Item target\out.asm.seq).Length -gt 0) {
        $compiled = $true
        break
    }
}
Stop-Xemu $p
if (-not $compiled) { throw "compile did not produce OUT.ASM within $CompileTimeout seconds" }
Write-Host ("OUT.ASM extracted: {0} bytes" -f (Get-Item target\out.asm.seq).Length)

Write-Host "=== link with runtime ==="
.\64tass.exe --cbm-prg --m45gs02 src\runtime\runtime.asm target\out.asm.seq -o target\out.prg
if ($LASTEXITCODE -ne 0) { throw "64tass link failed" }

if ($SkipRun) { Write-Host "=== done (link only) ==="; exit 0 }

Write-Host "=== phase 2: run OUT.PRG ==="
cmd /c ".\c1541.exe -attach `"$d81`" -delete out.prg -write target\out.prg out.prg >nul 2>nul"
Remove-Item -Force -ErrorAction SilentlyContinue $screenDump
$p = Start-Process -FilePath $Xemu -ArgumentList @(
    "-8", $d81, "-hdosvirt", "true",
    "-prg", (Join-Path $repo "target\bootstrap-run.prg"),
    "-dumpscreen", $screenDump, "-besure"
) -PassThru
Start-Sleep -Seconds $RunWait
Stop-Xemu $p -Graceful
if (-not (Test-Path $screenDump)) { throw "no screen dump produced" }

Write-Host "=== program output (last screen) ==="
Get-Content $screenDump | Where-Object { $_.Trim() -ne "" -and $_ -notmatch '^\{\$A0\}' }
