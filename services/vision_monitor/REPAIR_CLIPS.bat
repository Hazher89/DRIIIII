@echo off
REM Re-encode gamle MP4-klipp til H.264 slik at DriftPro web kan spille dem
cd /d "%~dp0"

if not exist .venv\Scripts\python.exe (
  echo Mangler .venv — kjør START_WINDOWS.bat forst.
  pause
  exit /b 1
)

call .venv\Scripts\activate.bat
python -m pip install -q imageio-ffmpeg
echo.
echo Reparerer gamle videoer (kan ta noen minutter)...
python repair_clips.py
echo.
pause
