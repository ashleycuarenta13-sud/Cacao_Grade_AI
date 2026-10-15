@echo off
title Cacao Grade AI - Flutter Web Client (HTTPS)

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

if not exist "%~dp0certs\cert.pem" (
    echo ==================================================
    echo   No TLS certificate found.
    echo.
    echo   Generate it first from the backend folder:
    echo.
    echo     cd backend
    echo     .venv\Scripts\python.exe make_cert.py
    echo ==================================================
    pause
    exit /b 1
)

echo ==================================================
echo   Cacao Grade AI Flutter app is starting over TLS.
echo.
echo   It opens in Chrome against https://127.0.0.1:8000
echo.
echo   Chrome will warn about the self-signed certificate
echo   on localhost - that is expected. Click
echo   Advanced, then Proceed to 127.0.0.1.
echo.
echo   Start the HTTPS services first, each in its own
echo   window:  RUN_CNN_SSL.bat  then  RUN_SSL.bat
echo.
echo   Press CTRL + C to stop.
echo ==================================================
echo.

flutter run -d chrome --dart-define=CACAO_API=https://127.0.0.1:8000

pause
