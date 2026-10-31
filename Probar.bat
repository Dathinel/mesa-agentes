@echo off
rem Corre las pruebas de la Cuadrilla en copias aisladas de %TEMP%, con CLI falsos: no gasta cuota ni toca datos\.
rem   Probar.bat                  todas
rem   Probar.bat probar-cuadrilla solo una
rem Variables: MESA_SIN_PAUSA=1 (sin pausa final).
setlocal EnableExtensions
chcp 65001 >nul
title Cuadrilla - pruebas
set "P=%~dp0pruebas"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set FALLOS=0
for %%T in (probar-cuadrilla caos-procesos) do (
  if /i "%~1"=="" call :una %%T
  if /i "%~1"=="%%T" call :una %%T
)
echo.
if "%FALLOS%"=="0" ( echo Todas las pruebas pasaron. ) else ( echo Fallaron %FALLOS% conjuntos de pruebas. )
if not defined MESA_SIN_PAUSA pause
exit /b %FALLOS%

:una
echo.
echo === %1 ===
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%P%\%1.ps1"
if errorlevel 1 set /a FALLOS+=1
exit /b 0
