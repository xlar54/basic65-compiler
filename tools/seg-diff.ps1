# Per-segment byte-diff for segmented (overlay) programs.
#
# A segmented OUT.ASM overlays every segment at the same window address
# with .logical/.here, so a single 64tass image is meaningless. Instead,
# assemble resident + ONE segment at a time (segments never reference
# each other -- the compiler gates cross-segment jumps), then check:
#   image k [0 .. len(out-native.prg))   == out-native.prg   (resident)
#   image k [len(out-native.prg) .. end) == out-native.s0k   (segment k)
#
# Expects the native artifacts already extracted from the D81:
#   target\out-native.prg, target\out-native.s00 .. s0(n-1)
# and the text output at target\out.asm.seq.
param(
    [string]$Asm = "target\out.asm.seq"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$lines = [IO.File]::ReadAllLines($Asm)

# find .logical/.here pairs
$blocks = @()
$open = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*\.logical\b') { $open = $i }
    elseif ($lines[$i] -match '^\s*\.here\b') {
        $blocks += ,@($open, $i)
        $open = -1
    }
}
if ($blocks.Count -lt 2) { Write-Host "not a segmented image ($($blocks.Count) blocks)"; exit 1 }
$prefixEnd = $blocks[0][0] - 1   # everything before the first .logical

$native = [IO.File]::ReadAllBytes("target\out-native.prg")
Write-Host ("resident (out-native.prg): {0} bytes, {1} segments" -f $native.Length, $blocks.Count)

$fail = $false
for ($k = 0; $k -lt $blocks.Count; $k++) {
    $piece = @()
    $piece += $lines[0..$prefixEnd]
    $piece += $lines[($blocks[$k][0])..($blocks[$k][1])]
    [IO.File]::WriteAllLines("target\seg-piece.asm", $piece)
    cmd /c ".\64tass.exe --cbm-prg --m45gs02 src\runtime\runtime.asm target\seg-piece.asm -o target\seg-piece.prg 2>&1" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "seg $k`: 64tass FAILED"
        cmd /c ".\64tass.exe --cbm-prg --m45gs02 src\runtime\runtime.asm target\seg-piece.asm -o target\seg-piece.prg 2>&1" | Select-Object -Last 6 | Out-Host
        $fail = $true; continue
    }
    $img = [IO.File]::ReadAllBytes("target\seg-piece.prg")
    $segfile = "target\out-native.s{0:d2}" -f $k
    $seg = [IO.File]::ReadAllBytes($segfile)

    # resident portion
    $resOk = $img.Length -ge $native.Length
    if ($resOk) {
        for ($i = 0; $i -lt $native.Length; $i++) {
            if ($img[$i] -ne $native[$i]) { $resOk = $false
                Write-Host ("seg $k`: RESIDENT diff at {0:x5}: 64tass={1:x2} native={2:x2}" -f $i, $img[$i], $native[$i]); break }
        }
    } else { Write-Host "seg $k`: image shorter than resident" }

    # segment portion
    $segOk = ($img.Length - $native.Length) -eq $seg.Length
    if (-not $segOk) {
        Write-Host ("seg $k`: length mismatch: 64tass tail {0} vs {1} {2}" -f ($img.Length - $native.Length), $segfile, $seg.Length)
    } else {
        for ($i = 0; $i -lt $seg.Length; $i++) {
            if ($img[$native.Length + $i] -ne $seg[$i]) { $segOk = $false
                Write-Host ("seg $k`: SEGMENT diff at +{0:x5}: 64tass={1:x2} native={2:x2}" -f $i, $img[$native.Length + $i], $seg[$i]); break }
        }
    }
    if ($resOk -and $segOk) { Write-Host ("seg $k`: byte-identical (resident {0} + segment {1})" -f $native.Length, $seg.Length) }
    else { $fail = $true }
}
if ($fail) { Write-Host "SEG-DIFF: FAIL"; exit 1 }
Write-Host "SEG-DIFF: all segments byte-identical"
exit 0
