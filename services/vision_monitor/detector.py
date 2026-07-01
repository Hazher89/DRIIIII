"""YOLOv8 person detection and entry tracking."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass

import numpy as np
from ultralytics import YOLO

logger = logging.getLogger(__name__)

# COCO class id for "person"
PERSON_CLASS_ID = 0


@dataclass(frozen=True)
class PersonDetection:
    track_id: int
    confidence: float
    bbox: tuple[int, int, int, int]  # x1, y1, x2, y2


class PersonEntryDetector:
    """
    Detects persons with YOLOv8 track mode and emits "entry" events
    when a new track id appears (with per-track cooldown).
    """

    def __init__(
        self,
        model_path: str,
        *,
        confidence_threshold: float = 0.45,
        entry_cooldown_seconds: float = 8.0,
    ) -> None:
        self._model_path = model_path
        self._model: YOLO | None = None
        self._confidence_threshold = confidence_threshold
        self._entry_cooldown_seconds = entry_cooldown_seconds
        self._seen_tracks: dict[int, float] = {}

    def _ensure_model(self) -> YOLO:
        if self._model is None:
            self._model = YOLO(self._model_path)
        return self._model

    def process_frame(self, frame: np.ndarray) -> list[PersonDetection]:
        """
        Run tracking on a BGR frame.
        Returns detections that represent a new person entry this frame.
        """
        results = self._ensure_model().track(
            frame,
            persist=True,
            classes=[PERSON_CLASS_ID],
            conf=self._confidence_threshold,
            verbose=False,
        )

        entries: list[PersonDetection] = []
        now = time.monotonic()

        if not results:
            return entries

        boxes = results[0].boxes
        if boxes is None or boxes.id is None:
            return entries

        ids = boxes.id.int().cpu().tolist()
        confs = boxes.conf.float().cpu().tolist()
        xyxy = boxes.xyxy.int().cpu().tolist()

        for track_id, conf, coords in zip(ids, confs, xyxy):
            last_seen = self._seen_tracks.get(track_id)
            if last_seen is not None and (now - last_seen) < self._entry_cooldown_seconds:
                continue

            self._seen_tracks[track_id] = now
            x1, y1, x2, y2 = coords
            entries.append(
                PersonDetection(
                    track_id=track_id,
                    confidence=float(conf),
                    bbox=(x1, y1, x2, y2),
                )
            )

        # Prune stale tracks to keep memory bounded.
        stale_before = now - (self._entry_cooldown_seconds * 10)
        self._seen_tracks = {
            tid: ts for tid, ts in self._seen_tracks.items() if ts >= stale_before
        }

        return entries

    def crop_person(self, frame: np.ndarray, detection: PersonDetection, *, padding: float = 0.08) -> np.ndarray:
        """High-quality crop of the detected person with optional padding."""
        h, w = frame.shape[:2]
        x1, y1, x2, y2 = detection.bbox
        bw, bh = x2 - x1, y2 - y1
        pad_x = int(bw * padding)
        pad_y = int(bh * padding)
        cx1 = max(0, x1 - pad_x)
        cy1 = max(0, y1 - pad_y)
        cx2 = min(w, x2 + pad_x)
        cy2 = min(h, y2 + pad_y)
        return frame[cy1:cy2, cx1:cx2].copy()
