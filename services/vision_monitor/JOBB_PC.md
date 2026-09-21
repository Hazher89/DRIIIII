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
LOCAL_DEV=true
```

3. Lagre og lukk Notisblokk

### 4. Start første gang
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

1. På jobb: workeren må kjøre (Del B)
2. Hjemme: åpne **driftpro.no** → **Mer → Søppelhåndtering**
3. Første versjon lagrer klipp lokalt på jobb-PC (`captures\`-mappen)  
   For at de skal synes i DriftPro fra skyen, må `LOCAL_DEV=false` + Dropbox/Supabase settes senere (spør agenten når worker kjører stabilt)

---

## Vanlige spørsmål

**Må DriftPro være åpen på jobb-PC?**  
Nei.

**Må min Mac hjemme være på?**  
Nei.

**Kan jeg bruke mydlink?**  
Ja, for å se live. Worker er for AI + lagring av klipp.

**Hva hvis XML i Chrome på kamera-IP?**  
Normal. Bruk `http://127.0.0.1:8090` i stedet.
