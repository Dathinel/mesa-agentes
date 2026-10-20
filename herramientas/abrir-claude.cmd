@echo off
rem Panel de Claude en la Mesa: reanuda la última conversación de esta carpeta; si no hay, o con 'nuevo', empieza una.
if /i not "%~2"=="nuevo" claude --continue --add-dir "%~1" && exit /b 0
claude --add-dir "%~1"
