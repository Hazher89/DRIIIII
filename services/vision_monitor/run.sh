#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -d .venv ]]; then
  python3 -m venv .venv
  .venv/bin/pip install -r requirements.txt
fi

echo "Starter vision monitor på http://127.0.0.1:${LOCAL_SERVER_PORT:-8090}"
echo "Flere kameraer: legg til i DriftPro → Mer → Kameraer"
exec .venv/bin/python multi_main.py
