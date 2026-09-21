@echo off
REM Start komprimator-sortering på Windows (dobbelklikk denne filen)
cd /d "%~dp0"

if not exist .env (
  copy .env.example .env
  echo.
  echo Opprettet .env — apne den i Notepad og sett CAMERA_PASSWORD.
  echo Deretter dobbeltklikk denne filen igjen.
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

set EVENT_TYPE=sorting_clip
set LOCAL_DEV=true

echo.
echo ========================================
echo  Sorteringsmonitor kjorer
echo  Dashboard: http://127.0.0.1:8090
echo  La dette vinduet staa apent.
echo  Lukk vinduet = stopp overvaking.
echo ========================================
echo.

python main.py
pause
