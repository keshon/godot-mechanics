@echo off
setlocal
set GODOT=e:\Programs\godot\Godot_v4.7.1-stable_win64.exe
if "%~1"=="" (
	"%GODOT%" --path "%~dp0."
) else (
	"%GODOT%" --path "%~dp0." -e
)
endlocal
