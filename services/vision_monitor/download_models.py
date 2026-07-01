#!/usr/bin/env python3
"""Last ned alle modeller: standard YOLO + Roboflow-prosjekter fra .env."""

from __future__ import annotations

import logging
import sys

from roboflow_downloader import MODELS_DIR, download_all_from_env, ensure_default_yolo

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("download_models")


def ensure_smart_uniform_models() -> None:
    """Gratis Ultralytics-modeller for pose (ankler) og YOLO-World (sko-typer)."""
    from pathlib import Path

    from ultralytics import YOLO

    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    for name in ("yolov8n-pose.pt", "yolov8s-worldv2.pt"):
        target = MODELS_DIR / name
        if target.is_file():
            logger.info("%s OK", name)
            continue
        logger.info("Laster ned %s …", name)
        YOLO(name)
        if Path(name).is_file():
            Path(name).rename(target)
            logger.info("Lagret %s", target)
        else:
            logger.warning("Kunne ikke laste %s — sko-deteksjon bruker heuristikk", name)


def main() -> int:
    ensure_default_yolo()
    logger.info("Standard yolov8n.pt OK")
    ensure_smart_uniform_models()

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
