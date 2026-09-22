@echo off
REM Start komprimator-sortering paa Windows (dobbelklikk denne filen)
cd /d "%~dp0"

if not exist .env (
  if exist C:\DriftPro\vision_monitor.env.bak (
    copy /Y C:\DriftPro\vision_monitor.env.bak .env
    echo Gjenopprettet .env fra backup.
  ) else if exist C:\DriftPro\DRIIIII_old\services\vision_monitor\.env (
    copy /Y C:\DriftPro\DRIIIII_old\services\vision_monitor\.env .env
    echo Gjenopprettet .env fra DRIIIII_old.
  ) else (
    copy .env.example .env
    echo.
    echo Opprettet .env - apne i Notepad og sett:
    echo   CAMERA_PASSWORD
    echo   LOCAL_DEV=false
    echo   SUPABASE_SERVICE_ROLE_KEY
    echo Deretter kjør: powershell -ExecutionPolicy Bypass -File .\ENABLE_DROPBOX.ps1
    pause
    exit /b 1
  )
)

where py >nul 2>&1
if %ERRORLEVEL%==0 (
  set PY=py -3
) else (
  where python >nul 2>&1
  if %ERRORLEVEL%==0 (
    set PY=python
  ) else (
    echo Python er ikke installert.
    echo Last ned fra https://www.python.org/downloads/
    echo Huk av "Add python.exe to PATH" under installasjon.
    pause
    exit /b 1
  )
)

if not exist .venv (
  echo Lager virtuelt miljo...
  %PY% -m venv .venv
  call .venv\Scripts\activate.bat
  pip install -r requirements.txt
) else (
  call .venv\Scripts\activate.bat
)

echo Laster modeller om nodvendig...
python download_models.py
python ensure_clip.py
if errorlevel 1 (
  echo.
  echo CLIP mangler — sortering vil feile. Prover pip direkte...
  python -m pip install openai-clip ftfy regex
)
python -m pip install -q imageio-ffmpeg

REM EVENT_TYPE / LOCAL_DEV / CLIP_* leses fra .env - ikke overstyr her.

echo.
echo ========================================
echo  Sorteringsmonitor kjorer
echo  Dashboard: http://127.0.0.1:8090
echo  Les innstillinger fra .env
echo  La dette vinduet staa apent.
echo  Lukk vinduet = stopp overvaking.
echo ========================================
echo.

python main.py
pause
