@echo off
setlocal EnableExtensions
title Minecraft Client Mods Sync
cd /d "%~dp0"

set "MANIFEST_URL=https://raw.githubusercontent.com/StellaSinora/minecraft-client-mods/main/mods.json"
set "SCRIPT_URL=https://raw.githubusercontent.com/StellaSinora/minecraft-client-mods/main/sync-mods.ps1"
set "MODS_DIR=%APPDATA%\.minecraft\mods"
set "PS1=%TEMP%\mc-sync-mods.ps1"

echo.
echo  ============================================
echo   Minecraft Client Mods Sync
echo  ============================================
echo  Manifest : %MANIFEST_URL%
echo  Mods dir : %MODS_DIR%
echo.

REM Always take the published script so every client runs the same sync.
echo  Downloading latest sync script...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%SCRIPT_URL%?t=%RANDOM%%RANDOM%' -OutFile '%PS1%' -UseBasicParsing"
if errorlevel 1 (
  if exist "%~dp0sync-mods.ps1" (
    echo  GitHub download failed. Using the script beside this bat.
    set "PS1=%~dp0sync-mods.ps1"
  ) else (
    echo  Failed to download sync-mods.ps1
    pause
    exit /b 1
  )
)

echo  Shader: Oculus + Embeddium
echo  Y = install Oculus and Embeddium
echo  N = normal download from mods.json
echo      Embeddium in mods.json stays either way. Oculus is only installed on Y.
echo.
set "ANSWER="
set /p ANSWER=  Install shader? [Y/N]: 
set "SHADER_ARG="
if /I "%ANSWER%"=="Y" set "SHADER_ARG=-InstallShaders"
if /I "%ANSWER%"=="YES" set "SHADER_ARG=-InstallShaders"
echo.

REM Always sync the published mods.json, not a copy saved beside this bat.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -ManifestUrl "%MANIFEST_URL%" -ModsDir "%MODS_DIR%" %SHADER_ARG%
set "ERR=%ERRORLEVEL%"

echo.
if "%ERR%"=="0" (
  echo  Done. You can start Minecraft now.
) else (
  echo  Sync failed. Error code: %ERR%
)
echo.
pause
exit /b %ERR%
