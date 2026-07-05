@echo off
setlocal

set BASIC_SOURCE=basic\source.bas
if not "%~1"=="" set BASIC_SOURCE=%~1

if not exist target mkdir target

del target\*.d81 2>nul
del target\*.lst 2>nul
del target\*.lbl 2>nul
del target\basic65c 2>nul
del target\ovr-rtstr1 2>nul
del target\ovr-rtstr2 2>nul
del target\ovr-rtcore 2>nul
del target\ovr-rtio 2>nul
del target\ovr-rtgc 2>nul
del target\ovr-rtnum 2>nul
del target\*.prg 2>nul

.\64tass.exe --cbm-prg -a src\basic65c.asm -l target\basic65c.lbl -L target\basic65c.lst -o target\basic65c
if errorlevel 1 exit /b 1

.\64tass.exe --cbm-prg -a src\overlays\ovr-rtstr1.asm -l target\ovr-rtstr1.lbl -L target\ovr-rtstr1.lst -o target\ovr-rtstr1
if errorlevel 1 exit /b 1

.\64tass.exe --cbm-prg -a src\overlays\ovr-rtstr2.asm -l target\ovr-rtstr2.lbl -L target\ovr-rtstr2.lst -o target\ovr-rtstr2
if errorlevel 1 exit /b 1

.\64tass.exe --cbm-prg -a src\overlays\ovr-rtcore.asm -l target\ovr-rtcore.lbl -L target\ovr-rtcore.lst -o target\ovr-rtcore
if errorlevel 1 exit /b 1

.\64tass.exe --cbm-prg -a src\overlays\ovr-rtio.asm -l target\ovr-rtio.lbl -L target\ovr-rtio.lst -o target\ovr-rtio
if errorlevel 1 exit /b 1

.\64tass.exe --cbm-prg -a src\overlays\ovr-rtgc.asm -l target\ovr-rtgc.lbl -L target\ovr-rtgc.lst -o target\ovr-rtgc
if errorlevel 1 exit /b 1

.\64tass.exe --cbm-prg -a src\overlays\ovr-rtnum.asm -l target\ovr-rtnum.lbl -L target\ovr-rtnum.lst -o target\ovr-rtnum
if errorlevel 1 exit /b 1

for %%F in (basic\*.bas) do (
    .\petcat.exe -w65 -l 2001 -o "target\%%~nF.prg" -- "%%F"
    if errorlevel 1 exit /b 1
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\fix-basic65-petcat-tokens.ps1 "target\%%~nF.prg"
    if errorlevel 1 exit /b 1
)

if /I not "%BASIC_SOURCE%"=="basic\source.bas" (
    .\petcat.exe -w65 -l 2001 -o target\source.prg -- "%BASIC_SOURCE%"
    if errorlevel 1 exit /b 1
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\fix-basic65-petcat-tokens.ps1 target\source.prg
    if errorlevel 1 exit /b 1
)

set HAVE_OUT_PRG=0
if exist target\out.asm.seq (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$out=(Get-Item -LiteralPath 'target\out.asm.seq').LastWriteTime; $deps=@($env:BASIC_SOURCE,'src\basic65c.asm','src\overlays\ovr-rtstr1.asm','src\overlays\ovr-rtstr2.asm','src\overlays\ovr-rtcore.asm','src\overlays\ovr-rtio.asm','src\overlays\ovr-rtgc.asm','src\overlays\ovr-rtnum.asm') + (Get-ChildItem -LiteralPath 'basic' -Filter '*.bas').FullName; foreach($dep in $deps){ if($out -lt (Get-Item -LiteralPath $dep).LastWriteTime){ exit 2 } }"
    if errorlevel 2 (
        echo Warning: target\out.asm.seq is stale; continuing without OUT.PRG
    ) else (
        .\64tass.exe --cbm-prg --m45gs02 target\out.asm.seq -o target\out.prg
        if errorlevel 1 (
            echo Warning: target\out.asm.seq did not assemble; continuing without OUT.PRG
            del target\out.prg 2>nul
        ) else (
            set HAVE_OUT_PRG=1
        )
    )
)

cd target
..\c1541.exe -format "basic65c,01" d81 basic65c.d81
if errorlevel 1 exit /b 1
..\c1541.exe -attach basic65c.d81 -write basic65c basic65c
if errorlevel 1 exit /b 1
..\c1541.exe -attach basic65c.d81 -write ovr-rtstr1 ovr-rtstr1
if errorlevel 1 exit /b 1
..\c1541.exe -attach basic65c.d81 -write ovr-rtstr2 ovr-rtstr2
if errorlevel 1 exit /b 1
..\c1541.exe -attach basic65c.d81 -write ovr-rtcore ovr-rtcore
if errorlevel 1 exit /b 1
..\c1541.exe -attach basic65c.d81 -write ovr-rtio ovr-rtio
if errorlevel 1 exit /b 1
..\c1541.exe -attach basic65c.d81 -write ovr-rtgc ovr-rtgc
if errorlevel 1 exit /b 1
..\c1541.exe -attach basic65c.d81 -write ovr-rtnum ovr-rtnum
if errorlevel 1 exit /b 1
for %%F in (*.prg) do (
    if /I not "%%F"=="out.prg" (
        ..\c1541.exe -attach basic65c.d81 -write "%%F" "%%F"
        if errorlevel 1 exit /b 1
    )
)
if "%HAVE_OUT_PRG%"=="1" (
    ..\c1541.exe -attach basic65c.d81 -write out.prg out.prg
    if errorlevel 1 exit /b 1
)
cd ..

echo Built target\basic65c.d81
echo Built BASIC test PRGs from basic\*.bas
if /I not "%BASIC_SOURCE%"=="basic\source.bas" echo Built SOURCE.PRG from %BASIC_SOURCE%
if "%HAVE_OUT_PRG%"=="1" echo Built target\out.prg and added it to the D81
