"""Last ned Roboflow YOLO-modeller til models/ for lokal inference."""

from __future__ import annotations

import logging
import os
import shutil
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

logger = logging.getLogger(__name__)

MODELS_DIR = Path(__file__).resolve().parent / "models"


@dataclass(frozen=True)
class RoboflowModelSpec:
    name: str
    workspace: str
    project: str
    version: int


def parse_model_specs(raw: str) -> list[RoboflowModelSpec]:
    """
    Format: name:workspace/project:version,name2:ws/proj2:2
    Eksempel: ppe:driftpro/ppe-vest-helmet/1,person:driftpro/person-entry/1
    """
    specs: list[RoboflowModelSpec] = []
    for chunk in raw.split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        try:
            name, rest, ver = chunk.split(":")
            ws, proj = rest.split("/", 1)
            specs.append(
                RoboflowModelSpec(
                    name=name.strip(),
                    workspace=ws.strip(),
                    project=proj.strip(),
                    version=int(ver.strip()),
                )
            )
        except ValueError as exc:
            raise ValueError(
                f"Ugyldig ROBOFLOW_MODELS entry {chunk!r}. "
                "Bruk format: navn:workspace/prosjekt:versjon"
            ) from exc
    return specs


def _find_weights(root: Path) -> Path | None:
    candidates = [
        root / "weights" / "best.pt",
        root / "train" / "weights" / "best.pt",
        root / "best.pt",
    ]
    for path in root.rglob("best.pt"):
        candidates.append(path)
    for path in candidates:
        if path.is_file() and path.stat().st_size > 10_000:
            return path
    return None


def download_model(spec: RoboflowModelSpec, *, api_key: str, models_dir: Path) -> Path:
    from roboflow import Roboflow

    models_dir.mkdir(parents=True, exist_ok=True)
    target = models_dir / f"{spec.name}.pt"
    staging = models_dir / f".download_{spec.name}"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)

    logger.info(
        "Laster ned Roboflow %s (%s/%s v%s)",
        spec.name,
        spec.workspace,
        spec.project,
        spec.version,
    )

    rf = Roboflow(api_key=api_key)
    version = (
        rf.workspace(spec.workspace)
        .project(spec.project)
        .version(spec.version)
    )

    # YOLOv8 PyTorch dataset export (inkluderer ofte weights + data.yaml)
    version.download(model_format="yolov8", location=str(staging))

    weights = _find_weights(staging)
    if weights is None:
        # Prøv Roboflow sin innebygde modell-referanse
        try:
            model = version.model
            if hasattr(model, "weights") and model.weights:
                weights = Path(model.weights)
        except Exception:
            weights = None

    if weights is None or not weights.is_file():
        shutil.rmtree(staging, ignore_errors=True)
        raise FileNotFoundError(
            f"Fant ingen best.pt for {spec.name}. "
            f"Sjekk at prosjektet har trente vekter på Roboflow."
        )

    shutil.copy2(weights, target)
    shutil.rmtree(staging, ignore_errors=True)
    logger.info("Lagret %s → %s", spec.name, target)
    return target


def download_all_from_env() -> list[Path]:
    load_dotenv()
    api_key = os.environ.get("ROBOFLOW_API_KEY", "").strip()
    models_raw = os.environ.get("ROBOFLOW_MODELS", "").strip()

    if not api_key:
        raise ValueError(
            "ROBOFLOW_API_KEY mangler i .env — hent nøkkel fra "
            "https://app.roboflow.com/settings/api"
        )
    if not models_raw:
        raise ValueError(
            "ROBOFLOW_MODELS mangler i .env — eksempel:\n"
            "ROBOFLOW_MODELS=ppe:mitt-workspace/ppe-detection/1,person:mitt-workspace/person/1"
        )

    specs = parse_model_specs(models_raw)
    out: list[Path] = []
    for spec in specs:
        out.append(download_model(spec, api_key=api_key, models_dir=MODELS_DIR))
    return out


def ensure_default_yolo(models_dir: Path | None = None) -> Path:
    """Sikrer at standard yolov8n.pt finnes (COCO person-deteksjon)."""
    from ultralytics import YOLO

    root = models_dir or MODELS_DIR
    root.mkdir(parents=True, exist_ok=True)
    target = root / "yolov8n.pt"
    if not target.is_file():
        logger.info("Laster ned standard yolov8n.pt …")
        YOLO("yolov8n.pt")
        if Path("yolov8n.pt").is_file():
            shutil.move("yolov8n.pt", target)
    return target
