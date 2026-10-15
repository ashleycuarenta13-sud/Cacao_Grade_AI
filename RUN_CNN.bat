@echo off
title Cacao Grade AI - CNN Inference Service

cd /d "%~dp0cnn_service"

echo ==================================================
echo   CNN inference service is starting...
echo.
echo   Predict endpoint:
echo   http://127.0.0.1:8001/predict
echo.
echo   Health check:
echo   http://127.0.0.1:8001/health
echo.
echo   Keep this window open - the backend forwards
echo   every uploaded photo here.
echo.
echo   Press CTRL + C to stop.
echo ==================================================
echo.

".venv\Scripts\python.exe" -m uvicorn main:app --host 127.0.0.1 --port 8001

pause
