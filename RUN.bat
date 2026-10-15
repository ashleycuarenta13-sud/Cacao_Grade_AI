@echo off
title Cacao Grade AI - Backend (API)

cd /d "%~dp0backend"

echo ==================================================
echo   Cacao Grade AI backend is starting...
echo.
echo   API + docs:
echo   http://127.0.0.1:8000/docs
echo.
echo   Health check:
echo   http://127.0.0.1:8000/health
echo.
echo   Flutter app (lahi nga terminal):
echo   cd frontend ^&^& flutter run -d chrome
echo.
echo   Press CTRL + C to stop.
echo ==================================================
echo.

".venv\Scripts\python.exe" -m uvicorn main:app --host 127.0.0.1 --port 8000

pause
