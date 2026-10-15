@echo off
title Cacao Grade AI - Backend (HTTPS)

cd /d "%~dp0backend"

if not exist "..\certs\cert.pem" (
  echo.
  echo   No certificate found in ..\certs
  echo   Generate one first:
  echo.
  echo     ".venv\Scripts\python.exe" make_cert.py
  echo.
  pause
  exit /b 1
)

echo ==================================================
echo   Cacao Grade AI backend is starting over HTTPS...
echo.
echo   API + docs:
echo   https://127.0.0.1:8000/docs
echo.
echo   Health check:
echo   https://127.0.0.1:8000/health
echo.
echo   Point the Flutter app at it:
echo   flutter run -d chrome --dart-define=CACAO_API=https://127.0.0.1:8000
echo.
echo   Note: the certificate is self-signed, so your
echo   browser will warn you once. Accept it for
echo   localhost; use a real certificate in public.
echo.
echo   Press CTRL + C to stop.
echo ==================================================
echo.

".venv\Scripts\python.exe" run.py --ssl

pause
