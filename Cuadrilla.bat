@echo off
rem Abre Cuadrilla: comprueba requisitos, archiva lo caducado, arranca el supervisor y el panel,
rem y abre Windows Terminal con Claude, Codex, agy y el tablero.
rem   Cuadrilla.bat                 abre la mesa y reanuda la última conversación de Claude
rem   Cuadrilla.bat nuevo           igual, pero Claude empieza una conversación nueva
rem   Cuadrilla.bat panel codex     reabre el panel de un agente (codex o agy) en la ventana de la mesa
rem   Cuadrilla.bat diagnostico     resumen pegable en el chat (estados, versiones, errores; sin secretos)
rem   Cuadrilla.bat pruebas         pruebas de caos y de la mesa en una copia aislada
rem   Cuadrilla.bat cerrar          para el supervisor y el panel; los hilos quedan listos para retomar
rem   Cuadrilla.bat prueba          solo muestra la orden de Windows Terminal, sin abrir nada
rem Variables: MESA_TRABAJO (carpeta de trabajo de los agentes; por defecto la que contiene la mesa).
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
title Cuadrilla

set "MESA=%~dp0"
if "%MESA:~-1%"=="\" set "MESA=%MESA:~0,-1%"
for %%I in ("%MESA%\..") do set "TRABAJO=%%~fI"
if defined MESA_TRABAJO set "TRABAJO=%MESA_TRABAJO%"
set "H=%MESA%\herramientas"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "PSA="%PS%" -NoProfile -ExecutionPolicy Bypass"
set "MODO="
if /i "%~1"=="nuevo" set "MODO=nuevo"

if /i "%~1"=="panel" goto panel
if /i "%~1"=="diagnostico" ( %PSA% -File "%H%\mesa.ps1" diagnostico & goto fin )
if /i "%~1"=="pruebas" ( call "%MESA%\Probar.bat" & goto fin )
if /i "%~1"=="cerrar" goto cerrar

set "WT=wt -w mesa new-tab --title Claude --tabColor #E8833A -d "%MESA%" cmd /k ""%H%\abrir-claude.cmd" "%TRABAJO%" %MODO%" ; split-pane -V --title Codex -d "%MESA%" %PSA% -File "%H%\trabajador.ps1" -Agente codex ; split-pane -H --title agy -d "%MESA%" %PSA% -File "%H%\trabajador.ps1" -Agente agy ; split-pane -H --title Tablero -d "%MESA%" %PSA% -File "%H%\tablero.ps1""
if /i "%~1"=="prueba" ( echo COMANDO_WT: %WT% & goto fin )

echo.
echo  ==============================================================================
echo   Cuadrilla: Claude, Codex y agy coordinados por archivos
echo  ==============================================================================
echo.
echo   Carpeta de trabajo: %TRABAJO%
echo.
set FALTA=0
for %%C in (claude codex agy wt) do (
  where %%C >nul 2>nul
  if errorlevel 1 ( echo   [FALTA] %%C no está en el PATH & set FALTA=1 ) else ( echo   [ok] %%C )
)
if "%FALTA%"=="1" (
  echo.
  echo   Falta algún programa: la mesa abre igual, pero ese panel no funcionará.
)
echo.
echo   Preparando la instalación (configuración e instrucciones de los agentes, solo si faltan)...
%PSA% -File "%H%\instalar.ps1"
echo   Archivando reclamos caducados y restos de la sesión anterior...
%PSA% -File "%H%\mesa.ps1" limpiar

echo   Arrancando el supervisor (sin modelo, en segundo plano)...
start "" /B %PSA% -WindowStyle Hidden -File "%H%\supervisor.ps1"

set "DATOS=%MESA%\datos"
if defined MESA_DATOS set "DATOS=%MESA_DATOS%"
set "PUERTO_FILE=%DATOS%\puerto.txt"
set PUERTO=
set ACTIVO=0
if exist "%PUERTO_FILE%" set /p PUERTO=<"%PUERTO_FILE%"
if defined PUERTO call :ping
if "!ACTIVO!"=="0" (
  echo   Arrancando el servidor de la oficina...
  start "" /B %PSA% -WindowStyle Hidden -File "%MESA%\panel\servidor.ps1"
  for /L %%i in (1,1,25) do (
    if "!ACTIVO!"=="0" (
      if exist "%PUERTO_FILE%" set /p PUERTO=<"%PUERTO_FILE%"
      if defined PUERTO call :ping
      if "!ACTIVO!"=="0" timeout /T 1 /NOBREAK >nul
    )
  )
)
if "!ACTIVO!"=="1" (
  echo   Oficina en http://127.0.0.1:!PUERTO!/
  start "" "http://127.0.0.1:!PUERTO!/"
) else echo   Aviso: la oficina no respondió; el resto de la mesa funciona igual.

echo   Abriendo Windows Terminal: Claude, Codex, agy y el tablero...
start "" %WT%
goto fin

:panel
if /i not "%~2"=="codex" if /i not "%~2"=="agy" ( echo Uso: Cuadrilla.bat panel codex^|agy & exit /b 1 )
start "" wt -w mesa new-tab --title %~2 -d "%MESA%" %PSA% -File "%H%\trabajador.ps1" -Agente %~2
goto fin

:cerrar
rem Los hilos, reclamos y puntos de control quedan en datos\: al volver, Cuadrilla.bat lo retoma todo.
%PSA% -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -match 'supervisor\.ps1|servidor\.ps1' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; 'Parado: ' + ($_.CommandLine -replace '.*\\','') }"
echo Cierra los paneles de Windows Terminal cuando sus agentes terminen: el encargo en curso queda en el hilo.
goto fin

:ping
"%PS%" -NoProfile -Command "try { $r = Invoke-WebRequest -Uri ('http://127.0.0.1:' + '%PUERTO%'.Trim() + '/api/ping') -TimeoutSec 1 -UseBasicParsing; exit [int]($r.StatusCode -ne 200) } catch { exit 1 }"
if not errorlevel 1 set ACTIVO=1
exit /b 0

:fin
endlocal
