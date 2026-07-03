@echo off
call build.bat
if errorlevel 1 exit /b 1

C:\Emulation\Mega65\xmega65.exe -8 "%CD%\target\basic65c.d81" -hdosvirt true 
