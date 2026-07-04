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
