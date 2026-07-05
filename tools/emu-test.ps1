# End-to-end fixture test: compile a BASIC fixture with the MEGA65-native
# compiler inside xemu, link the emitted assembly with the runtime, then run
# the compiled program and capture its screen output.
#
# Usage:
#   powershell -File tools\emu-test.ps1 [-Fixture basic\strings.bas]
#   powershell -File tools\emu-test.ps1 -All
#
# Phase 1 boots the compiler D81 and injects tools\bootstrap.bas, which
# presses RETURN (via the $D619 PETSCII injection register) to accept the
# default SOURCE.PRG and chain-loads BASIC65C. OUT.ASM appearing on the D81
# is the success signal: the compiler only renames OUT.TMP after a clean
# compile. Fixtures named in $NegativeFixtures must NOT produce OUT.ASM.
#
# Phase 2 writes the linked OUT.PRG back to the D81 and injects
# tools\bootstrap-run.bas, which chain-loads and runs it. The screen is
# dumped on emulator exit. Output containing "FAIL" marks the fixture
# suspect.
param(
    [string]$Fixture = "basic\source.bas",
    [string]$Xemu = "C:\Emulation\Mega65\xmega65.exe",
    [int]$CompileTimeout = 120,
    [int]$NegativeWait = 45,
    [int]$RunWait = 35,
    [switch]$SkipRun,
    [switch]$All
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

# fixtures that must fail to compile / that need interactive input
$NegativeFixtures = @("bad_data")
$SkipFixtures = @("ioarray")   # blocks on INPUT

$d81 = Join-Path $repo "target\basic65c.d81"
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

function Invoke-Fixture {
    param([string]$FixturePath)

    $name = [IO.Path]::GetFileNameWithoutExtension($FixturePath)
    $negative = $NegativeFixtures -contains $name
    $screenDump = Join-Path $repo "target\emu-screen-$name.txt"

    Write-Host "=== build: $FixturePath ==="
    cmd /c ".\build.bat $FixturePath" | Out-Null
    if ($LASTEXITCODE -ne 0) { return @{ Name = $name; Result = "BUILD FAILED" } }

    cmd /c ".\petcat.exe -w65 -l 2001 -o target\bootstrap.prg -- tools\bootstrap.bas 2>&1" | Out-Null
    cmd /c ".\petcat.exe -w65 -l 2001 -o target\bootstrap-run.prg -- tools\bootstrap-run.bas 2>&1" | Out-Null

    Write-Host "=== phase 1: compile $FixturePath on the MEGA65 ==="
    $p = Start-Process -FilePath $Xemu -ArgumentList @(
        "-8", $d81, "-hdosvirt", "true",
        "-prg", (Join-Path $repo "target\bootstrap.prg"), "-besure"
    ) -PassThru
    $waitFor = if ($negative) { $NegativeWait } else { $CompileTimeout }
    $deadline = (Get-Date).AddSeconds($waitFor)
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
    if ($negative -or -not $compiled) {
        Stop-Xemu $p
        if ($negative) {
            if ($compiled) { return @{ Name = $name; Result = "FAIL (compiled but should not)" } }
            return @{ Name = $name; Result = "PASS (rejected as expected)" }
        }
        return @{ Name = $name; Result = "FAIL (no OUT.ASM in $waitFor s)" }
    }
    Write-Host ("OUT.ASM extracted: {0} bytes" -f (Get-Item target\out.asm.seq).Length)

    # the native OUT.PRG is written right after OUT.ASM; keep the emulator
    # running until it lands
    Remove-Item -Force -ErrorAction SilentlyContinue target\out-native.prg
    $nativeDeadline = (Get-Date).AddSeconds(40)
    while ((Get-Date) -lt $nativeDeadline) {
        Start-Sleep -Seconds 5
        Copy-Item -Force $d81 $probe
        cmd /c ".\c1541.exe -attach `"$probe`" -read `"out.prg`" target\out-native.prg >nul 2>nul"
        if ((Test-Path target\out-native.prg) -and (Get-Item target\out-native.prg).Length -gt 0) { break }
    }
    Stop-Xemu $p

    Write-Host "=== link with runtime ==="
    cmd /c ".\64tass.exe --cbm-prg --m45gs02 src\runtime\runtime.asm target\out.asm.seq -o target\out.prg 2>&1" | Out-Host
    if ($LASTEXITCODE -ne 0) { return @{ Name = $name; Result = "FAIL (link error)" } }

    Write-Host "=== byte-diff: native OUT.PRG vs 64tass ==="
    $nativeOk = $false
    if ((Test-Path target\out-native.prg) -and (Get-Item target\out-native.prg).Length -gt 0) {
        cmd /c "fc /b target\out.prg target\out-native.prg >nul 2>nul"
        if ($LASTEXITCODE -eq 0) {
            $nativeOk = $true
            Write-Host "native OUT.PRG is byte-identical"
        } else {
            Write-Host "native OUT.PRG DIFFERS from 64tass output"
        }
    } else {
        Write-Host "native OUT.PRG missing"
    }

    if ($SkipRun) { return @{ Name = $name; Result = "PASS (link only)" } }

    Write-Host "=== phase 2: run OUT.PRG ==="
    if (-not $nativeOk) {
        # fall back to the 64tass-assembled PRG when the native one is absent
        cmd /c ".\c1541.exe -attach `"$d81`" -delete out.prg -write target\out.prg out.prg >nul 2>nul"
    }
    Remove-Item -Force -ErrorAction SilentlyContinue $screenDump
    $p = Start-Process -FilePath $Xemu -ArgumentList @(
        "-8", $d81, "-hdosvirt", "true",
        "-prg", (Join-Path $repo "target\bootstrap-run.prg"),
        "-dumpscreen", $screenDump, "-besure"
    ) -PassThru
    Start-Sleep -Seconds $RunWait
    Stop-Xemu $p -Graceful
    if (-not (Test-Path $screenDump)) { return @{ Name = $name; Result = "FAIL (no screen dump)" } }

    $screen = Get-Content $screenDump | Where-Object { $_.Trim() -ne "" -and $_ -notmatch '^\{\$A0\}' }
    Write-Host "=== program output (last screen) ==="
    $screen | ForEach-Object { Write-Host $_ }

    $ran = ($screen -join "`n") -match "READY\."
    $suspect = ($screen -join "`n") -match "FAIL"
    if (-not $ran) { return @{ Name = $name; Result = "FAIL (no READY after run)" } }
    if ($suspect) { return @{ Name = $name; Result = "SUSPECT (output contains FAIL)" } }
    if (-not $nativeOk) { return @{ Name = $name; Result = "SUSPECT (ran, but native PRG differs/missing)" } }
    return @{ Name = $name; Result = "PASS (native byte-identical)" }
}

$results = @()
if ($All) {
    foreach ($f in Get-ChildItem basic\*.bas) {
        $name = $f.BaseName
        if ($SkipFixtures -contains $name) {
            $results += @{ Name = $name; Result = "SKIPPED (interactive)" }
            continue
        }
        $results += Invoke-Fixture ("basic\" + $f.Name)
    }
} else {
    $results += Invoke-Fixture $Fixture
}

Write-Host ""
Write-Host "===== summary ====="
$failed = $false
foreach ($r in $results) {
    Write-Host ("{0,-12} {1}" -f $r.Name, $r.Result)
    if ($r.Result -like "FAIL*" -or $r.Result -like "SUSPECT*" -or $r.Result -like "BUILD*") { $failed = $true }
}
if ($failed) { exit 1 }
exit 0
