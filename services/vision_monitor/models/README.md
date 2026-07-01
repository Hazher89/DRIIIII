# Modellfiler (lastes ned med `python download_models.py`)

| Fil | Kilde |
|-----|--------|
| `yolov8n.pt` | Ultralytics COCO (person) — lastes alltid ned |
| `ppe.pt` | Roboflow — krever `ROBOFLOW_MODELS` i `.env` |
| `person.pt` | Roboflow — valgfritt ekstra prosjekt |

## Last ned alt

```bash
cd services/vision_monitor
source .venv/bin/activate
pip install -r requirements.txt
python download_models.py
```

Legg til i `.env`:

```
ROBOFLOW_API_KEY=din-nøkkel
ROBOFLOW_MODELS=ppe:mitt-workspace/ppe-vest-helmet/1
```

Bruk modellen i `.env`:

```
YOLO_MODEL=models/ppe.pt
```
