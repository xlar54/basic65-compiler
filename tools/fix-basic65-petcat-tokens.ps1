param(
    [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
    [string[]]$Path
)

$ErrorActionPreference = 'Stop'

foreach ($item in $Path) {
    $resolved = (Resolve-Path -LiteralPath $item).Path
    [byte[]]$bytes = [IO.File]::ReadAllBytes($resolved)
    $changed = 0

    if ($bytes.Length -lt 7) {
        continue
    }

    $pos = 2
    while ($pos + 4 -le $bytes.Length) {
        if ($bytes[$pos] -eq 0 -and $bytes[$pos + 1] -eq 0) {
            break
        }

        $lineStart = $pos + 4
        $lineEnd = $lineStart
        while ($lineEnd -lt $bytes.Length -and $bytes[$lineEnd] -ne 0) {
            $lineEnd++
        }
        if ($lineEnd -ge $bytes.Length) {
            throw "Malformed tokenized BASIC file: $item"
        }

        $inString = $false
        $inData = $false
        for ($i = $lineStart; $i -lt $lineEnd; $i++) {
            $b = $bytes[$i]

            if ($b -eq 0x22) {
                $inString = -not $inString
                continue
            }
            if ($inString) {
                continue
            }
            if ($b -eq 0x8f) {
                break
            }
            if ($b -eq 0x83) {
                $inData = $true
                continue
            }
            if ($inData) {
                if ($b -eq 0x3a) {
                    $inData = $false
                }
                continue
            }

            # VSYNC: newer ROM token petcat does not know at all
            if ($i + 4 -lt $lineEnd -and $b -eq 0x56 -and
                $bytes[$i+1] -eq 0x53 -and $bytes[$i+2] -eq 0x59 -and
                $bytes[$i+3] -eq 0x4e -and $bytes[$i+4] -eq 0x43) {
                $bytes[$i] = 0x20
                $bytes[$i+1] = 0x20
                $bytes[$i+2] = 0x20
                $bytes[$i+3] = 0xfe
                $bytes[$i+4] = 0x54
                $changed++
                $i += 4
                continue
            }
            # DECBIN: petcat emits the DEC token + literal BIN
            if ($i + 3 -lt $lineEnd -and $b -eq 0xd1 -and
                $bytes[$i+1] -eq 0x42 -and $bytes[$i+2] -eq 0x49 -and $bytes[$i+3] -eq 0x4e) {
                $bytes[$i] = 0x20
                $bytes[$i+1] = 0x20
                $bytes[$i+2] = 0xce
                $bytes[$i+3] = 0x11
                $changed++
                $i += 3
                continue
            }
            # STRBIN$: petcat leaves it as plain text
            if ($i + 6 -lt $lineEnd -and $b -eq 0x53 -and
                $bytes[$i+1] -eq 0x54 -and $bytes[$i+2] -eq 0x52 -and
                $bytes[$i+3] -eq 0x42 -and $bytes[$i+4] -eq 0x49 -and
                $bytes[$i+5] -eq 0x4e -and $bytes[$i+6] -eq 0x24) {
                for ($k = 0; $k -le 4; $k++) { $bytes[$i+$k] = 0x20 }
                $bytes[$i+5] = 0xce
                $bytes[$i+6] = 0x12
                $changed++
                $i += 6
                continue
            }
            if ($i + 1 -lt $lineEnd -and $b -eq 0x57) {
                if ($bytes[$i + 1] -eq 0x97) {
                    $bytes[$i] = 0xfe
                    $bytes[$i + 1] = 0x1d
                    $changed++
                    $i++
                    continue
                }
                if ($bytes[$i + 1] -eq 0xc2) {
                    $bytes[$i] = 0xce
                    $bytes[$i + 1] = 0x10
                    $changed++
                    $i++
                    continue
                }
            }
        }

        $pos = $lineEnd + 1
    }

    if ($changed -gt 0) {
        [IO.File]::WriteAllBytes($resolved, $bytes)
        Write-Host "Fixed $changed BASIC65 extended token(s) in $item"
    }
}
