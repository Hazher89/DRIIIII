"""Detect cardboard / bulky packaging near two compactors (YOLO-World, offline)."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np
from ultralytics import YOLO

logger = logging.getLogger(__name__)

# Prompt classes — packaging/boxes only, not the appliances themselves.
DEFAULT_CLASSES = [
    "brown cardboard box",
    "cardboard carton",
    "corrugated shipping box",
    "large appliance packaging carton",
    "oversized cardboard box with contents",
    "washing machine carton packaging",
    "refrigerator carton packaging",
]

BULKY_HINTS = (
    "large",
    "appliance",
    "oversized",
    "contents",
    "washing",
    "refrigerator",
    "carton packaging",
)


@dataclass(frozen=True)
class CompactorZone:
    name: str
    x0: float  # normalized 0..1
    x1: float
    y0: float
    y1: float

    def contains_center(self, cx: float, cy: float, width: int, height: int) -> bool:
        nx = cx / max(1, width)
        ny = cy / max(1, height)
        return self.x0 <= nx <= self.x1 and self.y0 <= ny <= self.y1


@dataclass(frozen=True)
class SortingHit:
    track_id: int
    confidence: float
    bbox: tuple[int, int, int, int]
    label: str
    reason: str  # cardboard | bulky_packaging
    zone: str
    annotated_frame: np.ndarray


class SortingDetector:
    """
    One camera covering two compactors.
    Triggers when cardboard or bulky packaging appears in a zone.
    """

    def __init__(
        self,
        model_path: str,
        *,
        classes: list[str] | None = None,
        confidence_threshold: float = 0.25,
        cooldown_seconds: float = 90.0,
        zones: list[CompactorZone] | None = None,
    ) -> None:
        self._model_path = model_path
        self._classes = classes or list(DEFAULT_CLASSES)
        self._confidence_threshold = confidence_threshold
        self._cooldown_seconds = cooldown_seconds
        self._zones = zones or [
            CompactorZone("komprimator_1", 0.0, 0.48, 0.15, 0.95),
            CompactorZone("komprimator_2", 0.52, 1.0, 0.15, 0.95),
        ]
        self._model: YOLO | None = None
        self._last_fire: dict[str, float] = {}

    def _ensure_model(self) -> YOLO:
        if self._model is None:
            path = self._model_path
            if not Path(path).is_file():
                # Ultralytics downloads by name if missing
                path = Path(path).name or "yolov8s-worldv2.pt"
            logger.info("Loading YOLO-World for sorting: %s", path)
            self._model = YOLO(path)
            if hasattr(self._model, "set_classes"):
                self._model.set_classes(self._classes)
        return self._model

    def analyze_frame(self, frame: np.ndarray) -> tuple[int, list[SortingHit], list[dict]]:
        """
        Returns (object_count, hits_to_record, feed_lines).
        Hits already respect per-zone cooldown.
        """
        model = self._ensure_model()
        results = model.predict(
            frame,
            conf=self._confidence_threshold,
            verbose=False,
        )
        h, w = frame.shape[:2]
        annotated = frame.copy()
        self._draw_zones(annotated, w, h)

        objects = 0
        candidates: list[SortingHit] = []
        feed: list[dict] = []
        now = time.monotonic()

        if not results:
            return 0, [], feed

        boxes = results[0].boxes
        names = results[0].names or {}
        if boxes is None or len(boxes) == 0:
            return 0, [], [
                {
                    "id": f"scan-{int(now)}",
                    "status": "ok",
                    "text": "Skanner begge komprimatorer…",
                }
            ]

        xyxy = boxes.xyxy.int().cpu().tolist()
        confs = boxes.conf.float().cpu().tolist()
        clss = boxes.cls.int().cpu().tolist() if boxes.cls is not None else [0] * len(xyxy)

        for i, (coords, conf, cls_id) in enumerate(zip(xyxy, confs, clss)):
            x1, y1, x2, y2 = coords
            cx = (x1 + x2) / 2.0
            cy = (y1 + y2) / 2.0
            label = str(names.get(cls_id, self._classes[cls_id] if cls_id < len(self._classes) else "box"))
            zone = self._zone_for(cx, cy, w, h)
            if zone is None:
                continue

            objects += 1
            reason = self._reason_for(label)
            color = (40, 160, 255) if reason == "cardboard" else (40, 80, 255)
            cv2.rectangle(annotated, (x1, y1), (x2, y2), color, 2)
            cv2.putText(
                annotated,
                f"{zone}:{reason} {conf:.2f}",
                (x1, max(20, y1 - 8)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.55,
                color,
                2,
                cv2.LINE_AA,
            )

            key = f"{zone}:{reason}"
            last = self._last_fire.get(key, 0.0)
            if now - last < self._cooldown_seconds:
                continue

            self._last_fire[key] = now
            candidates.append(
                SortingHit(
                    track_id=i + 1,
                    confidence=float(conf),
                    bbox=(x1, y1, x2, y2),
                    label=label,
                    reason=reason,
                    zone=zone,
                    annotated_frame=annotated,
                )
            )
            feed.append(
                {
                    "id": f"hit-{zone}-{int(now)}-{i}",
                    "status": "violation",
                    "text": f"{zone}: {reason} ({label})",
                }
            )

        if objects and not candidates:
            feed.append(
                {
                    "id": f"seen-{int(now)}",
                    "status": "ok",
                    "text": f"Ser {objects} objekt(er) — cooldown aktiv",
                }
            )
        elif not objects:
            feed.append(
                {
                    "id": f"scan-{int(now)}",
                    "status": "ok",
                    "text": "Skanner begge komprimatorer…",
                }
            )

        return objects, candidates, feed

    def _reason_for(self, label: str) -> str:
        low = label.lower()
        if any(h in low for h in BULKY_HINTS):
            return "bulky_packaging"
        return "cardboard"

    def _zone_for(self, cx: float, cy: float, w: int, h: int) -> str | None:
        for z in self._zones:
            if z.contains_center(cx, cy, w, h):
                return z.name
        return None

    def _draw_zones(self, frame: np.ndarray, w: int, h: int) -> None:
        for z in self._zones:
            x1 = int(z.x0 * w)
            x2 = int(z.x1 * w)
            y1 = int(z.y0 * h)
            y2 = int(z.y1 * h)
            cv2.rectangle(frame, (x1, y1), (x2, y2), (80, 200, 120), 2)
            cv2.putText(
                frame,
                z.name,
                (x1 + 8, y1 + 24),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.7,
                (80, 200, 120),
                2,
                cv2.LINE_AA,
            )

    @staticmethod
    def crop_person(frame: np.ndarray, detection: SortingHit, *, padding: float = 0.08) -> np.ndarray:
        """Reuse pipeline API — crop around the hit bbox."""
        h, w = frame.shape[:2]
        x1, y1, x2, y2 = detection.bbox
        bw, bh = x2 - x1, y2 - y1
        pad_x = int(bw * padding)
        pad_y = int(bh * padding)
        xa = max(0, x1 - pad_x)
        ya = max(0, y1 - pad_y)
        xb = min(w, x2 + pad_x)
        yb = min(h, y2 + pad_y)
        return frame[ya:yb, xa:xb].copy()
