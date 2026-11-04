@echo off
rem Abre el panel de ajuste: arranca el servidor local y el navegador. BLENDER: ruta a blender.exe (por defecto la de %USERPROFILE%\tools)
rem Opens the tuning panel: starts the local server and the browser. BLENDER: path to blender.exe (defaults to the one in %USERPROFILE%\tools)
if "%BLENDER%"=="" set "BLENDER=%USERPROFILE%\tools\blender-5.2\blender.exe"
python "%~dp0servidor.py"
if errorlevel 1 pause
