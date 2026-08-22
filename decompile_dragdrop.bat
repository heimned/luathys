@echo off
title Luathys Offline Decompiler
cd /d "%~dp0"

echo ========================================
echo   Luathys Offline Decompiler
echo ========================================
echo.

rem Find Python (python or py launcher)
set PY=
where python >nul 2>nul && set PY=python
if not defined PY (
    where py >nul 2>nul && set PY=py
)
if not defined PY (
    echo [ERROR] Python not found on this PC.
    echo Install it from https://www.python.org/downloads/
    echo and check "Add Python to PATH" during install.
    echo.
    pause
    exit /b 1
)

rem Check unluau.exe exists here
if not exist unluau.exe (
    echo [ERROR] unluau.exe not found in this folder:
    echo         %cd%
    echo Download it and place it next to this .bat file.
    echo.
    pause
    exit /b 1
)

rem Check the script exists here
if not exist decompile_all.py (
    echo [ERROR] decompile_all.py not found in this folder.
    echo.
    pause
    exit /b 1
)

rem Folder argument: passed by drag-drop, or ask user
set "TARGET=%~1"
if not defined TARGET (
    echo Drag your dump folder onto this .bat file,
    echo or paste the full folder path below.
    echo Example: C:\Users\you\AppData\Local\Madium\Workspace\Ugc_130960021905304
    echo.
    set /p TARGET=Folder path:
)

if not exist "%TARGET%" (
    echo [ERROR] Folder does not exist: %TARGET%
    echo.
    pause
    exit /b 1
)

echo.
echo Decompiling everything in:
echo   %TARGET%
echo.
%PY% decompile_all.py "%TARGET%"
echo.
echo ========================================
echo   Done. Window stays open.
echo ========================================
pause