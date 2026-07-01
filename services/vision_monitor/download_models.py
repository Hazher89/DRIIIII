#!/usr/bin/env python3
"""Last ned alle modeller: standard YOLO + Roboflow-prosjekter fra .env."""

from __future__ import annotations

import logging
import sys

from roboflow_downloader import download_all_from_env, ensure_default_yolo

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("download_models")


def main() -> int:
    ensure_default_yolo()
    logger.info("Standard yolov8n.pt OK")

    try:
        paths = download_all_from_env()
    except ValueError as exc:
        logger.warning("%s", exc)
        logger.info(
            "Roboflow-modeller hoppet over. Legg til i .env:\n"
            "  ROBOFLOW_API_KEY=din-nøkkel\n"
            "  ROBOFLOW_MODELS=ppe:workspace/prosjekt/1"
        )
        return 0

    for p in paths:
        logger.info("Roboflow modell klar: %s", p)
    return 0


if __name__ == "__main__":
    sys.exit(main())
