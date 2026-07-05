@echo off
setlocal

set BASIC_SOURCE=basic\source.bas
if not "%~1"=="" set BASIC_SOURCE=%~1

if not exist target mkdir target

del target\*.d81 2>nul
del target\*.lst 2>nul
del target\*.lbl 2>nul
del target\basic65c 2>nul
del target\runtime.prg 2>nul
del target\*.prg 2>nul

.\64tass.exe --cbm-prg -a src\basic65c.asm -l target\basic65c.lbl -L target\basic65c.lst -o target\basic65c
if errorlevel 1 exit /b 1

rem Assemble the runtime standalone as a syntax/size check and to publish its
rem label map. The runtime is linked into generated programs below; this
rem artifact is not shipped on the D81.
.\64tass.exe --cbm-prg -a src\runtime\runtime.asm -l target\runtime.lbl -L target\runtime.lst -o target\runtime.prg
if errorlevel 1 exit /b 1

rem Derive binary code templates from the compiler's text templates for the
rem native backend (see docs\native-backend.md). Requires Python; skipped
rem with a warning if unavailable because nothing consumes the output yet.
where python >nul 2>nul
if %ERRORLEVEL%==0 (
    python tools\gen-bin-templates.py
    if errorlevel 1 exit /b 1
) else (
    echo Warning: python not found; skipping bin-template generation
)

rem harness bootstraps must survive the target\*.prg wipe above
.\petcat.exe -w65 -l 2001 -o target\bootstrap.prg -- tools\bootstrap.bas
if errorlevel 1 exit /b 1
.\petcat.exe -w65 -l 2001 -o target\bootstrap-run.prg -- tools\bootstrap-run.bas
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
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$out=(Get-Item -LiteralPath 'target\out.asm.seq').LastWriteTime; $deps=@($env:BASIC_SOURCE,'src\basic65c.asm','src\runtime\runtime.asm') + (Get-ChildItem -LiteralPath 'basic' -Filter '*.bas').FullName; foreach($dep in $deps){ if($out -lt (Get-Item -LiteralPath $dep).LastWriteTime){ exit 2 } }"
    if errorlevel 2 (
        echo Warning: target\out.asm.seq is stale; continuing without OUT.PRG
    ) else (
        .\64tass.exe --cbm-prg --m45gs02 src\runtime\runtime.asm target\out.asm.seq -o target\out.prg
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
..\c1541.exe -attach basic65c.d81 -write runtime.prg runtime.prg
if errorlevel 1 exit /b 1
for %%F in (*.prg) do (
    if /I not "%%F"=="out.prg" if /I not "%%F"=="runtime.prg" (
        ..\c1541.exe -attach basic65c.d81 -write "%%F" "%%F"
        if errorlevel 1 exit /b 1
    )
)
rem out.prg is no longer pre-loaded onto the D81: the compiler writes its
rem own native OUT.PRG there during compilation
cd ..

echo Built target\basic65c.d81
echo Built BASIC test PRGs from basic\*.bas
if /I not "%BASIC_SOURCE%"=="basic\source.bas" echo Built SOURCE.PRG from %BASIC_SOURCE%
if "%HAVE_OUT_PRG%"=="1" echo Built target\out.prg and added it to the D81
