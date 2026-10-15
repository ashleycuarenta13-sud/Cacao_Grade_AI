@echo off
title Cacao Grade AI - CNN Inference Service (HTTPS)

cd /d "%~dp0cnn_service"

if not exist "..\certs\cert.pem" (
  echo.
  echo   No certificate found in ..\certs
  echo   Generate one first (from backend\):
  echo.
  echo     ..\backend\.venv\Scripts\python.exe ..\backend\make_cert.py
  echo.
  pause
  exit /b 1
)

echo ==================================================
echo   CNN inference service is starting over HTTPS...
echo.
echo   Predict endpoint:
echo   https://127.0.0.1:8001/predict
echo.
echo   Health check:
echo   https://127.0.0.1:8001/health
echo.
echo   Keep this window open - the backend forwards
echo   every uploaded photo here. Start the backend
echo   with RUN_SSL.bat so it trusts this certificate.
echo.
echo   Press CTRL + C to stop.
echo ==================================================
echo.

".venv\Scripts\python.exe" run.py --ssl

pause
