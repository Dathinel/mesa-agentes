@echo off
rem Panel de Claude en la Mesa: reanuda la conversación de la mesa (datos\sesion-claude.txt, que guarda el hook de inicio);
rem si no la hay, la última de esta carpeta; con 'nuevo', una nueva.
set "DATOS=%~dp0..\datos"
if defined MESA_DATOS set "DATOS=%MESA_DATOS%"
set SID=
if exist "%DATOS%\sesion-claude.txt" set /p SID=<"%DATOS%\sesion-claude.txt"
if /i "%~2"=="nuevo" goto nueva
if defined SID claude --resume %SID% --add-dir "%~1" && exit /b 0
claude --continue --add-dir "%~1" && exit /b 0
:nueva
claude --add-dir "%~1"
