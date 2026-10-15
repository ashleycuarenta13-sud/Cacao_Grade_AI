@echo off
title Cacao Grade AI - Flutter Web Client

cd /d "%~dp0frontend"

where flutter >nul 2>nul
if errorlevel 1 (
    echo ==================================================
    echo   Flutter is not on PATH in this window.
    echo.
    echo   Install or repair it, then open a NEW terminal
    echo   and run this file again.
    echo.
    echo   https://docs.flutter.dev/get-started/install
    echo ==================================================
    pause
    exit /b 1
)

echo ==================================================
echo   Cacao Grade AI Flutter app is starting...
echo.
echo   It opens in Chrome. Keep this window open -
echo   press R in it to hot-reload, Q to quit.
echo.
echo   Before this, start both services in their own
echo   windows:  RUN_CNN.bat  then  RUN.bat
echo.
echo   For the HTTPS setup use RUN_FLUTTER_SSL.bat
echo   instead of this file.
echo.
echo   Press CTRL + C to stop.
echo ==================================================
echo.

flutter run -d chrome

pause
