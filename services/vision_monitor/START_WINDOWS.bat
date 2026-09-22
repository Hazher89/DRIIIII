@echo off
REM Start komprimator-sortering på Windows (dobbelklikk denne filen)
cd /d "%~dp0"

if not exist .env (
  copy .env.example .env
  echo.
  echo Opprettet .env — apne den i Notepad og sett:
  echo   CAMERA_PASSWORD
  echo   LOCAL_DEV=false   (for Dropbox/DriftPro video)
  echo   SUPABASE_SERVICE_ROLE_KEY
  echo Deretter dobbeltklikk denne filen igjen.
  echo Eller kjør ENABLE_DROPBOX.ps1 for produksjon.
  pause
  exit /b 1
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

REM EVENT_TYPE / LOCAL_DEV / CLIP_* leses fra .env — ikke overstyr her.
REM Produksjon: LOCAL_DEV=false + ENABLE_DROPBOX.ps1 (2+2 min MP4 til DriftPro).

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
