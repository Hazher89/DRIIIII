"""Vernesko vs joggesko — YOLO-Pose ankler + YOLO-World klassifisering."""

from __future__ import annotations

import logging
from pathlib import Path

import cv2
import numpy as np

logger = logging.getLogger(__name__)

MODELS_DIR = Path(__file__).resolve().parent / "models"

# COCO pose — ankler
_ANKLE_LEFT = 15
_ANKLE_RIGHT = 16

_BOOT_CLASSES = (
    "safety boot",
    "steel toe boot",
    "work boot",
    "construction boot",
    "hiking boot",
)
_CASUAL_CLASSES = (
    "sneaker",
    "running shoe",
    "trainer",
    "tennis shoe",
    "casual shoe",
)


class ShoeAnalyzer:
    """Finner føtter via pose og skiller vernesko fra joggesko (gratis Ultralytics-modeller)."""

    def __init__(
        self,
        *,
        models_dir: Path | None = None,
        safety_threshold: float = 0.28,
        casual_threshold: float = 0.22,
    ) -> None:
        self._models_dir = models_dir or MODELS_DIR
        self._safety_threshold = safety_threshold
        self._casual_threshold = casual_threshold
        self._pose_model = None
        self._world_model = None
        self._world_classes: list[str] | None = None

    def _ensure_pose(self):
        if self._pose_model is not None:
            return self._pose_model
        from ultralytics import YOLO

        path = self._models_dir / "yolov8n-pose.pt"
        if not path.is_file():
            logger.info("Laster ned yolov8n-pose.pt …")
            YOLO("yolov8n-pose.pt")
            if Path("yolov8n-pose.pt").is_file():
                Path("yolov8n-pose.pt").rename(path)
        self._pose_model = YOLO(str(path))
        return self._pose_model

    def _ensure_world(self):
        if self._world_model is not None:
            return self._world_model
        from ultralytics import YOLO

        for name in ("yolov8s-worldv2.pt", "yolov8s-world.pt"):
            path = self._models_dir / name
            if not path.is_file():
                try:
                    logger.info("Laster ned %s …", name)
                    YOLO(name)
                    if Path(name).is_file():
                        Path(name).rename(path)
                except Exception as exc:
                    logger.warning("Kunne ikke laste %s: %s", name, exc)
                    continue
            if path.is_file():
                self._world_model = YOLO(str(path))
                self._world_classes = list(_BOOT_CLASSES) + list(_CASUAL_CLASSES)
                self._world_model.set_classes(self._world_classes)
                return self._world_model
        return None

    def score(
        self, frame: np.ndarray, bbox: tuple[int, int, int, int]
    ) -> tuple[bool, float]:
        """Returnerer (mangler_vernesko, safety_score 0–1)."""
        foot_rois = self._foot_rois(frame, bbox)
        if not foot_rois:
            return False, 0.5

        boot_hits = 0.0
        casual_hits = 0.0
        heuristic_safety = 0.0

        world = self._ensure_world()
        for roi in foot_rois:
            heuristic_safety = max(heuristic_safety, self._boot_heuristic(roi))
            if world is None:
                continue
            try:
                results = world.predict(roi, conf=0.12, verbose=False)
            except Exception:
                continue
            if not results or results[0].boxes is None:
                continue
            boxes = results[0].boxes
            if len(boxes) == 0:
                continue
            names = results[0].names or {}
            for cls_id, conf in zip(
                boxes.cls.int().cpu().tolist(),
                boxes.conf.float().cpu().tolist(),
            ):
                label = names.get(int(cls_id), "").lower()
                if any(b in label for b in _BOOT_CLASSES):
                    boot_hits = max(boot_hits, float(conf))
                if any(c in label for c in _CASUAL_CLASSES):
                    casual_hits = max(casual_hits, float(conf))

        safety_score = max(boot_hits, heuristic_safety * 0.75)
        has_boots = boot_hits >= self._safety_threshold
        has_casual = casual_hits >= self._casual_threshold

        if has_boots and not has_casual:
            return False, safety_score
        if has_casual and not has_boots:
            return True, max(0.0, 1.0 - casual_hits)
        if has_casual and has_boots:
            # Foretrekk tydeligere klassifisering.
            if casual_hits > boot_hits + 0.08:
                return True, max(0.0, 1.0 - casual_hits)
            return False, safety_score

        # Ingen tydelig YOLO-World treff — bruk heuristikk (mørk, massiv såle).
        missing = heuristic_safety < 0.34
        return missing, safety_score

    def _foot_rois(
        self, frame: np.ndarray, bbox: tuple[int, int, int, int]
    ) -> list[np.ndarray]:
        x1, y1, x2, y2 = bbox
        h, w = frame.shape[:2]
        bw, bh = x2 - x1, y2 - y1
        if bh < 100:
            return []

        rois: list[np.ndarray] = []
        ankles = self._ankle_points(frame, bbox)

        if ankles:
            for ax, ay in ankles:
                if ax <= 0 or ay <= 0:
                    continue
                pad = max(28, int(bh * 0.09))
                fx1 = max(0, int(ax - pad * 1.4))
                fx2 = min(w, int(ax + pad * 1.4))
                fy1 = max(0, int(ay - pad * 0.35))
                fy2 = min(h, int(ay + pad * 1.15))
                if fx2 - fx1 > 20 and fy2 - fy1 > 20:
                    rois.append(frame[fy1:fy2, fx1:fx2])
        else:
            # YOLO-person-boks dekker ofte ikke føttene — forleng nedover.
            extend = int(bh * 0.18)
            foot_y1 = max(0, y2 - max(24, int(bh * 0.12)))
            foot_y2 = min(h, y2 + extend)
            foot_x1 = max(0, x1 + int(bw * 0.02))
            foot_x2 = min(w, x2 - int(bw * 0.02))
            if foot_y2 - foot_y1 > 16 and foot_x2 - foot_x1 > 24:
                rois.append(frame[foot_y1:foot_y2, foot_x1:foot_x2])
                # To separate soner (venstre/høyre fot).
                mid = (foot_x1 + foot_x2) // 2
                rois.append(frame[foot_y1:foot_y2, foot_x1:mid])
                rois.append(frame[foot_y1:foot_y2, mid:foot_x2])

        return [r for r in rois if r.size > 0]

    def _ankle_points(
        self, frame: np.ndarray, bbox: tuple[int, int, int, int]
    ) -> list[tuple[float, float]]:
        try:
            model = self._ensure_pose()
            x1, y1, x2, y2 = bbox
            pad = int((y2 - y1) * 0.08)
            h, w = frame.shape[:2]
            crop = frame[
                max(0, y1 - pad) : min(h, y2 + int((y2 - y1) * 0.2)),
                max(0, x1 - pad) : min(w, x2 + pad),
            ]
            if crop.size == 0:
                return []
            results = model.predict(crop, conf=0.25, verbose=False)
            if not results or results[0].keypoints is None:
                return []
            kps = results[0].keypoints
            if kps.xy is None or len(kps.xy) == 0:
                return []
            pts = kps.xy[0].cpu().numpy()
            confs = None
            if kps.conf is not None and len(kps.conf) > 0:
                confs = kps.conf[0].cpu().numpy()
            off_y = max(0, y1 - pad)
            off_x = max(0, x1 - pad)
            out: list[tuple[float, float]] = []
            for idx in (_ANKLE_LEFT, _ANKLE_RIGHT):
                if idx >= len(pts):
                    continue
                x, y = float(pts[idx][0]), float(pts[idx][1])
                vis = float(confs[idx]) if confs is not None and idx < len(confs) else 1.0
                if vis < 0.25 or x <= 1 or y <= 1:
                    continue
                out.append((x + off_x, y + off_y))
            return out
        except Exception as exc:
            logger.debug("Pose ankle lookup failed: %s", exc)
            return []

    @staticmethod
    def _boot_heuristic(roi: np.ndarray) -> float:
        """Mørke, robuste arbeidssko — ikke hvite joggesko."""
        hsv = cv2.cvtColor(roi, cv2.COLOR_BGR2HSV)
        sat = float(np.mean(hsv[:, :, 1]))
        val = float(np.mean(hsv[:, :, 2]))
        gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)

        dark_ratio = float(np.mean(gray < 88))
        low_sat_ratio = float(np.mean(hsv[:, :, 1] < 55))
        bright_ratio = float(np.mean(gray > 175))

        score = 0.0
        if val < 105:
            score += 0.35
        if dark_ratio > 0.38:
            score += 0.35
        if low_sat_ratio > 0.45:
            score += 0.2
        if bright_ratio > 0.28:
            score -= 0.45  # hvite joggesko
        if sat > 70 and bright_ratio > 0.2:
            score -= 0.25

        return max(0.0, min(1.0, score))
