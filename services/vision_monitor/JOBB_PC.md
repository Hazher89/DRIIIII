# Jobb-PC Windows — steg for steg (nybegynner)

Du trenger **ikke** ha DriftPro åpen i nettleseren.
Du trenger bare at denne workeren kjører.

---

## Del A — Én gang (oppsett)

### 1. Installer Python
1. Gå til https://www.python.org/downloads/
2. Last ned Python 3.12 eller 3.11
3. Kjør installasjonen
4. **Huk av** «Add python.exe to PATH» nederst
5. Klikk Install Now

### 2. Kopier DriftPro vision-mappen til PC-en
På jobb-PC, lag f.eks. mappe:
`C:\DriftPro\vision_monitor\`

Kopier inn **hele innholdet** fra repoet:
`services/vision_monitor/`  
(alle filer: `START_WINDOWS.bat`, `main.py`, `.env`, osv.)

Enklest: last ned ZIP fra GitHub, eller kopier USB/mappe fra Mac.

### 3. Sett kamera-passord
1. I mappen: høyreklikk `.env` → Åpne med **Notisblokk**
2. Sjekk at dette står (endre bare om IP er byttet):

```
CAMERA_HOST=192.168.39.190
CAMERA_USER=admin
CAMERA_PASSWORD=964281
EVENT_TYPE=sorting_clip
LOCAL_DEV=false
CLIP_SECONDS_BEFORE=60
CLIP_SECONDS_AFTER=120
```

3. Lagre og lukk Notisblokk

### 4. Aktiver Dropbox / DriftPro (anbefalt)
```
cd C:\DriftPro\DRIIIII\services\vision_monitor
powershell -ExecutionPolicy Bypass -File .\ENABLE_DROPBOX.ps1
```
Setter `LOCAL_DEV=false` + service_role. Uten dette lagres video kun lokalt.

### 5. Start første gang
1. Dobbeltklikk **`START_WINDOWS.bat`**
2. Første gang kan det ta flere minutter (laster ned programmer)
3. Når det står at den kjører: åpne Chrome på jobb-PC →  
   **http://127.0.0.1:8090**  
   Du skal se kamera-bildet

Hvis feil om kamera: sjekk at PC og kamera er på **samme WiFi/nett**, og at IP stemmer.

---

## Del B — Hver dag / 24/7

1. La PC være **på** (ikke hvilemodus — i Windows:  
   Innstillinger → System → Strøm → aldri sov når den er tilkoblet strøm)
2. Dobbeltklikk **`START_WINDOWS.bat`** etter oppstart  
   **eller** legg snarvei i Oppstart-mappen (Win+R → `shell:startup` → lim inn snarvei til bat-filen)
3. La det **svarte vinduet stå åpent** — lukker du det, stopper overvåkingen

---

## Del C — Se klipp hjemme i DriftPro

1. På jobb: workeren må kjøre med **`LOCAL_DEV=false`** (Del A4)
2. Hjemme: åpne **driftpro.no** → **Mer → Søppelhåndtering**
3. Ved **feilkasting** lastes **MP4** (1 min før personen kom + 2 min etter de går) til Dropbox + `vision_events`. Riktig sortering lagres ikke.
4. Logg på jobb-PC skal vise: `Sorting VIDEO uploaded`

---

## Vanlige spørsmål

**Cloud Agent / Cursor i skyen sier den ikke er Windows?**  
Riktig. Kameraet ligger på jobb-nettet (`192.168.39.190`). Sky-agenten er Linux og når det ikke.  
Kjør **lokalt på jobb-PC**: åpne `C:\DriftPro\...` i Cursor (Local), eller bare dobbeltklikk `START_WINDOWS.bat` — du trenger ikke Cursor for å kjøre workeren.

**`camera_error: Could not read snapshot ... Set CAMERA_USER and CAMERA_PASSWORD`**  
Betyr: workeren på jobb-PC fikk ikke bilde fra kameraet. Vanligst:

1. `.env` mangler eller har tom `CAMERA_PASSWORD` (første `START_WINDOWS.bat` kopierer bare `.env.example`)
2. Feil passord
3. PC er ikke på samme nett som kameraet

Sjekk i Notisblokk at `.env` har:

```
CAMERA_HOST=192.168.39.190
CAMERA_USER=admin
CAMERA_PASSWORD=964281
```

Lagre → start `START_WINDOWS.bat` på nytt → åpne http://127.0.0.1:8090

**Kan jeg lagre til Dropbox?**  
Ja. Fra Mac er `vision-camera` deployet. På jobb-PC:

```
cd C:\DriftPro\DRIIIII\services\vision_monitor
git pull
powershell -ExecutionPolicy Bypass -File .\ENABLE_DROPBOX.ps1
```

Scriptet setter `LOCAL_DEV=false`, `COMPANY_ID`, og ber om `service_role`-nøkkel.  
Deretter start `START_WINDOWS.bat` på nytt. Ved treff lastes **video (MP4)** til Dropbox.

**Må DriftPro være åpen på jobb-PC?**  
Nei.

**Må min Mac hjemme være på?**  
Nei.

**Kan jeg bruke mydlink?**  
Ja, for å se live. Worker er for AI + lagring av klipp.

**Hva hvis XML i Chrome på kamera-IP?**  
Normal. Bruk `http://127.0.0.1:8090` i stedet.

**Læremodus?**  
I DriftPro → Søppelhåndtering / kamera: slå på **Læremodus**. Worker tar opp kontinuerlig til du stopper, deretter merker du riktig/feil i appen.