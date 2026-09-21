# DriftPro Vision Monitor

Production async Python service: **RTSP camera → YOLOv8 person entry → Dropbox snapshot → Supabase row**.

## Architecture

```
┌─────────────┐    ┌──────────────┐    ┌─────────────────┐    ┌──────────────────┐
│ RTSP Camera │───▶│ OpenCV read  │───▶│ YOLOv8 track    │───▶│ Person entry     │
│  (IP cam)   │    │ (camera.py)  │    │ (detector.py)   │    │ event            │
└─────────────┘    └──────────────┘    └─────────────────┘    └────────┬─────────┘
                                                                         │
                    ┌────────────────────────────────────────────────────┘
                    ▼
         ┌────────────────────┐    ┌────────────────────┐    ┌────────────────────┐
         │ JPEG crop snapshot │───▶│ Dropbox upload     │───▶│ Supabase insert    │
         │ (high quality)     │    │ + shareable URL    │    │ vision_events      │
         └────────────────────┘    └────────────────────┘    └────────────────────┘
```

| Module | Responsibility |
|--------|----------------|
| `main.py` | Async entrypoint, graceful shutdown |
| `config.py` | Environment settings |
| `camera.py` | OpenCV RTSP capture + JPEG encode |
| `detector.py` | Ultralytics YOLOv8 person tracking |
| `dropbox_client.py` | Dropbox SDK upload + public share link |
| `db_client.py` | Async `httpx` → Supabase REST |
| `pipeline.py` | End-to-end orchestration |

## Install

```bash
cd services/vision_monitor
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate

pip install -r requirements.txt
```

Or install packages individually:

```bash
pip install ultralytics opencv-python-headless dropbox httpx python-dotenv numpy
```

> **Note:** On a machine with a GPU, `ultralytics` will use it automatically. For CPU-only edge devices, use `yolov8n.pt`.

## Configure

```bash
cp .env.example .env
# Edit .env with RTSP URL, Supabase service role, Dropbox token, company UUID
```

Apply database migration:

```bash
supabase db push
# or run supabase/migrations/20260630120000_vision_events.sql in Dashboard
```

## Run

```bash
python main.py
```

One process per camera. For multiple cameras, run separate instances with different `CAMERA_ID` / `RTSP_URL` / `EVENT_TYPE`.

## Dropbox folder layout

```
/DriftPro/vision/company_<uuid>/<camera_id>/YYYY/MM/DD/<timestamp>_<camera>_<event>.jpg
```

Aligns with existing DriftPro Dropbox root (`/DriftPro/...`).

## Web platform integration

Query `vision_events` from Flutter/Supabase:

```dart
final rows = await supabase
  .from('vision_events')
  .select()
  .eq('company_id', companyId)
  .order('occurred_at', ascending: false);
// row['dropbox_image_url'] → use directly in Image.network(...)
```

## Event types

| `EVENT_TYPE` | Use case |
|--------------|----------|
| `sorting_clip` | **Komprimatorer:** brun eske / stor emballasje → 1 min før+etter video |
| `ppe_violation` | HMS / PPE zone monitoring |
| `uniform_violation` | MAVI uniform + vernesko |
| `parking_entry` | Vehicle/person entry tracking |
| `parking_exit` | Exit events (future zone logic) |

## Komprimator-sortering (klar for kun IP)

Én D-Link/IP-kamera som ser **begge** komprimatorene. Offline YOLO-World finner:
- brune pappesker
- stor/full emballasje (vaskemaskin-/kjøleskap-*eske*, ikke selve maskinen)

Ved treff lagres **~1 min før + 1 min etter** som video i `captures/`.

```bash
cd services/vision_monitor
./run_sorting.sh
# Åpne http://127.0.0.1:8090
```

I `.env` (fra `.env.example`) sett typisk bare:

```bash
CAMERA_HOST=192.168.x.x
CAMERA_PASSWORD=...   # hvis kamera krever det
```

Soner (venstre/høyre) justeres med `ZONE1_RECT` / `ZONE2_RECT` (`x0,y0,x1,y1` 0–1).

### Må jeg være på jobb for å koble kamera?

**mydlink-appen** hjemmefra = sky/relay. Den viser live i appen, men DriftPro-workeren trenger **lokal IP** (`192.168…`) eller RTSP på samme nett.

| Situasjon | Fungerer? |
|-----------|-----------|
| PC/Mac **på jobb** samme WiFi/LAN som kamera | Ja — sett `CAMERA_HOST` |
| Du hjemme, bare mydlink-app | Nei — workeren får ikke lokal IP via appen |
| VPN inn på jobb-nett hjemmefra | Ofte ja |
| Worker kjører alltid på en PC på lageret | Beste løsning |

Du trenger altså **ikke** stå foran kameraet for å utvikle koden, men for **live deteksjon** må workeren nå kameraets lokale adresse.

PPE-specific class detection can extend `detector.py` with a custom YOLO weights file.

## Register as a DriftPro feature

1. Deploy migration `20260630120000_vision_events.sql` (+ `20260920120000_vision_sorting_clip.sql`)
2. Run this service on edge hardware (NVR / mini PC) per camera
3. Add Flutter screen under HMS or admin that lists `vision_events`
4. Reuse existing Dropbox OAuth (`company_dropbox_connections`) or dedicated vision app token
