"""MAVI uniform + vernesko detection on person crops."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

from detector import PERSON_CLASS_ID, PersonDetection, PersonEntryDetector

logger = logging.getLogger(__name__)

_LOGO_PATH = Path(__file__).resolve().parent / "assets" / "mavi_logo.png"


@dataclass(frozen=True)
class UniformViolation:
    track_id: int
    confidence: float
    bbox: tuple[int, int, int, int]
    missing_logo: bool
    missing_shoes: bool
    logo_score: float
    shoes_score: float


class UniformViolationDetector:
    """
    Tracks persons and flags missing MAVI chest logo and/or safety shoes.
    Uses template matching for logo; heuristic for dark footwear in foot ROI.
    """

    def __init__(
        self,
        model_path: str,
        *,
        logo_template_path: Path | None = None,
        confidence_threshold: float = 0.45,
        violation_cooldown_seconds: float = 12.0,
        logo_match_threshold: float = 0.45,
        shoes_score_threshold: float = 0.32,
    ) -> None:
        self._person = PersonEntryDetector(
            model_path,
            confidence_threshold=confidence_threshold,
            entry_cooldown_seconds=0.5,
        )
        self._violation_cooldown = violation_cooldown_seconds
        self._logo_threshold = logo_match_threshold
        self._shoes_threshold = shoes_score_threshold
        self._last_violation: dict[int, float] = {}
        self._last_feed: dict[int, tuple[str, float]] = {}
        self._track_hits: dict[int, int] = {}
        self._violation_streak: dict[int, int] = {}
        self._min_track_frames = 6
        self._min_violation_streak = 2
        self._min_violation_conf = 0.42
        self._min_person_height_px = 160
        self._logo_templates = self._load_logo_templates(logo_template_path or _LOGO_PATH)

    def _load_logo_templates(self, path: Path) -> list[np.ndarray]:
        if not path.is_file():
            logger.warning("MAVI logo template missing at %s", path)
            return []

        img = cv2.imread(str(path), cv2.IMREAD_COLOR)
        if img is None:
            return []

        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        h, w = gray.shape[:2]
        templates: list[np.ndarray] = []
        for scale in (0.35, 0.5, 0.7, 1.0, 1.3):
            tw = max(24, int(w * scale))
            th = max(24, int(h * scale))
            templates.append(cv2.resize(gray, (tw, th), interpolation=cv2.INTER_AREA))
        logger.info("Loaded %s MAVI logo template scales from %s", len(templates), path)
        return templates

    def process_frame(self, frame: np.ndarray) -> list[UniformViolation]:
        """Return violations detected this frame (respecting per-track cooldown)."""
        detections = self._detect_persons(frame)
        return self._violations_from_detections(frame, detections)

    def analyze_frame(
        self, frame: np.ndarray
    ) -> tuple[int, list[UniformViolation], list[dict[str, object]]]:
        """Én YOLO-kjøring — telling, brudd og live-feed-linjer."""
        detections = self._detect_persons(frame)
        visible = self._visible_persons(detections)
        stable = self._stable_detections(visible)
        assessed = [self._assess_person(frame, det) for det in stable]
        feed = self._feed_from_assessed(assessed)
        violations = self._violations_from_assessed(assessed)
        return len(visible), violations, feed

    def _visible_persons(self, detections: list[PersonDetection]) -> list[PersonDetection]:
        out: list[PersonDetection] = []
        for det in detections:
            if det.confidence < self._person._confidence_threshold:  # noqa: SLF001
                continue
            bh = det.bbox[3] - det.bbox[1]
            if bh < self._min_person_height_px:
                continue
            out.append(det)
        return out

    def _stable_detections(self, detections: list[PersonDetection]) -> list[PersonDetection]:
        seen: set[int] = set()
        stable: list[PersonDetection] = []

        for det in detections:
            hits = self._track_hits.get(det.track_id, 0) + 1
            self._track_hits[det.track_id] = hits
            seen.add(det.track_id)
            if hits >= self._min_track_frames:
                stable.append(det)

        for track_id in list(self._track_hits.keys()):
            if track_id in seen:
                continue
            self._track_hits[track_id] = max(0, self._track_hits[track_id] - 1)
            if self._track_hits[track_id] == 0:
                del self._track_hits[track_id]

        return stable

    def _assess_person(
        self, frame: np.ndarray, det: PersonDetection
    ) -> tuple[PersonDetection, bool, bool, float, float]:
        missing_logo, logo_score = self._check_logo(frame, det.bbox)
        missing_shoes, shoes_score = self._check_shoes(frame, det.bbox)
        return det, missing_logo, missing_shoes, logo_score, shoes_score

    def _feed_from_assessed(
        self,
        assessed: list[tuple[PersonDetection, bool, bool, float, float]],
    ) -> list[dict[str, object]]:
        feed: list[dict[str, object]] = []
        now = time.monotonic()

        for det, missing_logo, missing_shoes, _, _ in assessed:
            if det.confidence < self._min_violation_conf:
                continue
            bh = det.bbox[3] - det.bbox[1]
            if bh < self._min_person_height_px:
                continue

            if missing_logo or missing_shoes:
                status = "violation"
                parts: list[str] = []
                if missing_logo:
                    parts.append("mangler MAVI-logo")
                if missing_shoes:
                    parts.append("mangler vernesko")
                text = f"Avvik — {' og '.join(parts)}"
            else:
                status = "ok"
                text = "Godkjent uniform — MAVI-logo og vernesko"

            last = self._last_feed.get(det.track_id)
            if last is not None and last[0] == status and (now - last[1]) < 2.8:
                continue
            self._last_feed[det.track_id] = (status, now)

            feed.append(
                {
                    "id": f"{det.track_id}-{status}-{int(now * 1000)}",
                    "track_id": det.track_id,
                    "status": status,
                    "text": text,
                }
            )

        stale = now - 60.0
        self._last_feed = {
            tid: (st, ts) for tid, (st, ts) in self._last_feed.items() if ts >= stale
        }
        return feed

    def _violations_from_assessed(
        self,
        assessed: list[tuple[PersonDetection, bool, bool, float, float]],
    ) -> list[UniformViolation]:
        violations: list[UniformViolation] = []
        now = time.monotonic()

        for det, missing_logo, missing_shoes, logo_score, shoes_score in assessed:
            if det.confidence < self._min_violation_conf:
                continue
            bh = det.bbox[3] - det.bbox[1]
            if bh < self._min_person_height_px:
                continue

            last = self._last_violation.get(det.track_id)
            if last is not None and (now - last) < self._violation_cooldown:
                continue

            if not missing_logo and not missing_shoes:
                self._violation_streak.pop(det.track_id, None)
                continue

            streak = self._violation_streak.get(det.track_id, 0) + 1
            self._violation_streak[det.track_id] = streak
            if streak < self._min_violation_streak:
                continue

            self._last_violation[det.track_id] = now
            violations.append(
                UniformViolation(
                    track_id=det.track_id,
                    confidence=det.confidence,
                    bbox=det.bbox,
                    missing_logo=missing_logo,
                    missing_shoes=missing_shoes,
                    logo_score=logo_score,
                    shoes_score=shoes_score,
                )
            )
            logger.info(
                "Uniform brudd track=%s logo=%s (%.2f) sko=%s (%.2f)",
                det.track_id,
                missing_logo,
                logo_score,
                missing_shoes,
                shoes_score,
            )

        stale = now - (self._violation_cooldown * 8)
        self._last_violation = {
            tid: ts for tid, ts in self._last_violation.items() if ts >= stale
        }
        active_tracks = {det.track_id for det, *_ in assessed}
        self._violation_streak = {
            tid: s for tid, s in self._violation_streak.items() if tid in active_tracks
        }
        return violations

    def _violations_from_detections(
        self,
        frame: np.ndarray,
        detections: list[PersonDetection],
    ) -> list[UniformViolation]:
        assessed = [self._assess_person(frame, det) for det in detections]
        return self._violations_from_assessed(assessed)

    def _detect_persons(self, frame: np.ndarray) -> list[PersonDetection]:
        """Alle personer i bildet — track med fallback til predict."""
        model = self._person._ensure_model()  # noqa: SLF001
        conf = self._person._confidence_threshold  # noqa: SLF001
        small, scale = self._resize_for_yolo(frame)

        results = model.track(
            small,
            persist=True,
            classes=[PERSON_CLASS_ID],
            conf=conf,
            imgsz=1280,
            verbose=False,
        )
        out = self._boxes_to_detections(results, scale)
        return out

    @staticmethod
    def _boxes_to_detections(
        results,
        scale: float,
    ) -> list[PersonDetection]:
        out: list[PersonDetection] = []
        if not results:
            return out
        boxes = results[0].boxes
        if boxes is None or len(boxes) == 0 or boxes.id is None:
            return out

        inv = 1.0 / scale
        confs = boxes.conf.float().cpu().tolist()
        xyxy = boxes.xyxy.float().cpu().tolist()
        ids = boxes.id.int().cpu().tolist()

        for track_id, conf, coords in zip(ids, confs, xyxy):
            x1, y1, x2, y2 = coords
            out.append(
                PersonDetection(
                    track_id=int(track_id),
                    confidence=float(conf),
                    bbox=(
                        int(x1 * inv),
                        int(y1 * inv),
                        int(x2 * inv),
                        int(y2 * inv),
                    ),
                )
            )
        return out

    @staticmethod
    def _resize_for_yolo(frame: np.ndarray) -> tuple[np.ndarray, float]:
        h, w = frame.shape[:2]
        max_w = 1280
        if w <= max_w:
            return frame, 1.0
        scale = max_w / w
        small = cv2.resize(frame, (max_w, int(h * scale)), interpolation=cv2.INTER_AREA)
        return small, scale

    def _check_logo(self, frame: np.ndarray, bbox: tuple[int, int, int, int]) -> tuple[bool, float]:
        if not self._logo_templates:
            return False, 1.0

        x1, y1, x2, y2 = bbox
        h, w = frame.shape[:2]
        bw, bh = x2 - x1, y2 - y1
        if bw < 40 or bh < 80:
            return False, 1.0

        chest_y1 = y1 + int(bh * 0.12)
        chest_y2 = y1 + int(bh * 0.48)
        chest_x1 = x1 + int(bw * 0.18)
        chest_x2 = x2 - int(bw * 0.18)
        chest_y1, chest_y2 = max(0, chest_y1), min(h, chest_y2)
        chest_x1, chest_x2 = max(0, chest_x1), min(w, chest_x2)
        roi = frame[chest_y1:chest_y2, chest_x1:chest_x2]
        if roi.size == 0:
            return False, 1.0

        gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
        best = 0.0
        for tmpl in self._logo_templates:
            th, tw = tmpl.shape[:2]
            if gray.shape[0] < th + 4 or gray.shape[1] < tw + 4:
                continue
            res = cv2.matchTemplate(gray, tmpl, cv2.TM_CCOEFF_NORMED)
            _, max_val, _, _ = cv2.minMaxLoc(res)
            best = max(best, float(max_val))

        return best < self._logo_threshold, best

    def _check_shoes(self, frame: np.ndarray, bbox: tuple[int, int, int, int]) -> tuple[bool, float]:
        x1, y1, x2, y2 = bbox
        h, w = frame.shape[:2]
        bw, bh = x2 - x1, y2 - y1
        if bh < 100:
            return False, 1.0

        foot_y1 = y2 - max(12, int(bh * 0.1))
        foot_y2 = y2
        foot_x1 = x1 + int(bw * 0.08)
        foot_x2 = x2 - int(bw * 0.08)
        foot_y1, foot_y2 = max(0, foot_y1), min(h, foot_y2)
        foot_x1, foot_x2 = max(0, foot_x1), min(w, foot_x2)
        roi = frame[foot_y1:foot_y2, foot_x1:foot_x2]
        if roi.size == 0:
            return False, 1.0

        hsv = cv2.cvtColor(roi, cv2.COLOR_BGR2HSV)
        sat = float(np.mean(hsv[:, :, 1]))
        val = float(np.mean(hsv[:, :, 2]))
        edges = cv2.Canny(cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY), 60, 150)
        edge_density = float(np.count_nonzero(edges)) / max(1, edges.size)

        # Dark, low-saturation footwear + some edge structure → likely vernesko.
        dark_score = 0.0
        if val < 95:
            dark_score += 0.45
        if sat < 55:
            dark_score += 0.25
        if edge_density > 0.04:
            dark_score += 0.35

        missing = dark_score < self._shoes_threshold
        return missing, dark_score

    def count_persons(self, frame: np.ndarray) -> int:
        return len(self._detect_persons(frame))

    def crop_person(
        self,
        frame: np.ndarray,
        detection: UniformViolation | PersonDetection,
        *,
        padding: float = 0.08,
    ) -> np.ndarray:
        return self._person.crop_person(frame, detection, padding=padding)
