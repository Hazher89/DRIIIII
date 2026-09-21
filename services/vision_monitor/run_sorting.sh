#!/bin/bash
# Start komprimator-sortering (én kamera, begge soner, 1 min før/etter).
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Opprettet .env fra .env.example — sett CAMERA_HOST (og evt. CAMERA_PASSWORD)."
fi

if [[ ! -d .venv ]]; then
  python3 -m venv .venv
  .venv/bin/pip install -r requirements.txt
fi

.venv/bin/python download_models.py || true

export EVENT_TYPE="${EVENT_TYPE:-sorting_clip}"
export LOCAL_DEV="${LOCAL_DEV:-true}"

echo "Sorteringsmonitor → http://127.0.0.1:${LOCAL_SERVER_PORT:-8090}"
echo "Sett CAMERA_HOST i .env til kameraets lokale IP (på jobb-nett)."
exec .venv/bin/python main.py
