# Tekst til Cursor på Windows-PC (lim inn som én oppgave)

Du er **lokal agent på jobb-PC (Windows)**. Ikke Cloud Agent. Mål: full vision-setup slik at Mac/DriftPro kan se nesten-live og styre via git + Cursor worker.

## A) Git + repo
1. Installer Git hvis mangler: `winget install --id Git.Git -e --source winget`
2. Åpne **ny** PowerShell etter install.
3. Repo skal ligge på `C:\DriftPro\DRIIIII` (klon hvis mangler):
   ```
   mkdir C:\DriftPro -Force
   cd C:\DriftPro
   git clone https://github.com/Hazher89/DRIIIII.git
   ```
4. `cd C:\DriftPro\DRIIIII` → `git pull origin main`
5. Åpne workspace i Cursor: `C:\DriftPro\DRIIIII`

## B) Cursor My Machines worker (slik Mac kan styre denne PC-en)
```
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
# Hvis agent ikke finnes:
irm 'https://cursor.com/install?win32=true' | iex
agent login
cd C:\DriftPro\DRIIIII
agent worker start --name "jobb-pc" --worker-dir C:\DriftPro\DRIIIII
```
Hold dette vinduet åpent. Deretter kan Mac bruke environment **jobb-pc** på cursor.com/agents.

## C) .env for kamera + Dropbox + live + soner A/B
Mappe: `C:\DriftPro\DRIIIII\services\vision_monitor`

Sett/oppdater `.env` (opprett fra `.env.example` hvis mangler):

```
CAMERA_HOST=192.168.39.190
CAMERA_USER=admin
CAMERA_PASSWORD=964281
CAMERA_ID=cam-komprimatorer
VISION_CAMERA_ID=5f823a5a-6466-42bc-b52f-b56aa5136302
CAMERA_MODE=auto
EVENT_TYPE=sorting_clip
LOCAL_DEV=false
LOCAL_SERVER=true
LOCAL_SERVER_PORT=8090
LIVE_PUSH_INTERVAL_SECONDS=2
SUPABASE_URL=https://ksnnyccthotjbrmgjgdc.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<lim inn service_role fra Supabase API settings>
COMPANY_ID=00000000-0000-0000-0000-000000000000
ZONE1_NAME=container_A_papp
ZONE1_RECT=0.0,0.15,0.48,0.95
ZONE2_NAME=container_B_annet
ZONE2_RECT=0.52,0.15,1.0,0.95
CONFIDENCE_THRESHOLD=0.25
ENTRY_COOLDOWN_SECONDS=90
CLIP_SECONDS_BEFORE=60
CLIP_SECONDS_AFTER=60
CLIP_FPS=2
SORTING_MODEL=models/yolov8s-worldv2.pt
```

Hent `SUPABASE_SERVICE_ROLE_KEY` her:
https://supabase.com/dashboard/project/ksnnyccthotjbrmgjgdc/settings/api
(Reveal **service_role**, ikke anon)

## D) Start vision worker
```
cd C:\DriftPro\DRIIIII\services\vision_monitor
.\START_WINDOWS.bat
```
La vinduet stå åpent.

Sjekk:
- Ingen `camera_error`
- http://127.0.0.1:8090 viser bilde
- Etter ~10 s: live frames lastes til Dropbox (VISION_CAMERA_ID)

## E) Ferdig-kriterier (rapporter tilbake)
- [ ] `git pull` OK, siste commit på main
- [ ] `agent worker` kjører som `jobb-pc`
- [ ] `START_WINDOWS.bat` kjører uten camera_error
- [ ] Lokal live på :8090 OK
- [ ] `.env` har LOCAL_DEV=false + SERVICE_ROLE + VISION_CAMERA_ID + ZONE1/ZONE2

## Viktig
- Mac endrer kode → `git pull` på Windows + restart bat (eller agent worker henter og restarter).
- Live i DriftPro verden rundt = nesten-live JPEG hvert ~2s via Dropbox (ikke RTSP gjennom skyen).
- Deteksjon A=papp / B=annet styres av ZONE1_* / ZONE2_* i .env (Mac kan endre defaults i repo).
