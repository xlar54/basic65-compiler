@echo off
setlocal

if not exist target mkdir target

del target\*.d81 2>nul
del target\*.lst 2>nul
del target\*.lbl 2>nul
del target\basic65c 2>nul
del target\source.prg 2>nul
del target\out.prg 2>nul

.\64tass.exe --cbm-prg -a src\basic65c.asm -l target\basic65c.lbl -L target\basic65c.lst -o target\basic65c
if errorlevel 1 exit /b 1

.\petcat.exe -w65 -l 2001 -o target\source.prg -- basic\source.bas
if errorlevel 1 exit /b 1

set HAVE_OUT_PRG=0
if exist target\out.asm.seq (
    .\64tass.exe --cbm-prg --m45gs02 target\out.asm.seq -o target\out.prg
    if errorlevel 1 exit /b 1
    set HAVE_OUT_PRG=1
)

cd target
..\c1541.exe -format "basic65c,01" d81 basic65c.d81
if errorlevel 1 exit /b 1
..\c1541.exe -attach basic65c.d81 -write basic65c basic65c
if errorlevel 1 exit /b 1
..\c1541.exe -attach basic65c.d81 -write source.prg source.prg
if errorlevel 1 exit /b 1
if "%HAVE_OUT_PRG%"=="1" (
    ..\c1541.exe -attach basic65c.d81 -write out.prg out.prg
    if errorlevel 1 exit /b 1
)
cd ..

echo Built target\basic65c.d81
if "%HAVE_OUT_PRG%"=="1" echo Built target\out.prg and added it to the D81
