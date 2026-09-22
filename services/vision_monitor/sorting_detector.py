"""Detect bad waste sorting at two compactors (YOLO-World, offline).

Rules (MAVI):
  Container A = papp — only FLATTENED cardboard. Unflattened / bulky boxes = violation.
  Container B = annet (isopor etc.) — styrofoam OK. Whole cardboard box dumped here = violation.

OK example: empty trash into B, fold box, throw flat cardboard in A — no clip.
Clips are only saved when a person throws wrong (pipeline: 1 min before arrival,
2 min after they leave). Correct sorting is never stored.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np
from ultralytics import YOLO

logger = logging.getLogger(__name__)

# Prompts: skill flat sheet vs standing 3D box (unngå «oversized with contents»).
DEFAULT_CLASSES = [
    "flat collapsed cardboard sheet",
    "flattened cardboard lying flat",
    "standing unopened cardboard box",
    "tall cardboard box not flattened",
    "brown cardboard carton",
    "corrugated shipping box standing upright",
    "bulky cardboard packaging not flattened",
    "white styrofoam packaging",
    "expanded polystyrene foam block",
    "foam packing material",
]

STYROFOAM_HINTS = (
    "styrofoam",
    "polystyrene",
    "foam",
    "isopor",
    "eps",
)

CARDBOARD_HINTS = (
    "cardboard",
    "carton",
    "corrugated",
    "shipping box",
    "packaging",
)

# Sterke 3D-signaler i label (brukes kun sammen med geometri).
BULKY_HINTS = (
    "standing",
    "upright",
    "unopened",
    "not flattened",
    "tall",
    "bulky",
    "appliance",
    "washing",
    "refrigerator",
)

FLAT_HINTS = (
    "flat",
    "collapsed",
    "flattened",
    "folded",
    "sheet",
    "lying flat",
)

# Minimum conf for unflattened_cardboard (etter global + per-reason delta).
UNFLATTENED_MIN_CONF = 0.35


@dataclass(frozen=True)
class CompactorZone:
    name: str
    x0: float
    x1: float
    y0: float
    y1: float

    def contains_center(self, cx: float, cy: float, width: int, height: int) -> bool:
        nx = cx / max(1, width)
        ny = cy / max(1, height)
        return self.x0 <= nx <= self.x1 and self.y0 <= ny <= self.y1

    @property
    def is_papp_zone(self) -> bool:
        n = self.name.lower()
        return "papp" in n or n.endswith("_a") or "container_a" in n or n.startswith("a_")

    @property
    def is_annet_zone(self) -> bool:
        n = self.name.lower()
        return (
            "annet" in n
            or "isopor" in n
            or n.endswith("_b")
            or "container_b" in n
            or n.startswith("b_")
        )


@dataclass(frozen=True)
class SortingHit:
    track_id: int
    confidence: float
    bbox: tuple[int, int, int, int]
    label: str
    reason: str  # unflattened_cardboard | cardboard_in_wrong_bin
    zone: str
    annotated_frame: np.ndarray


@dataclass
class _ReasonFeedback:
    """Per-årsak justering fra menneske-merking."""

    conf_delta: float = 0.0
    suppress_until: float = 0.0  # monotonic; midlertidig demp etter mange «correct»


class SortingDetector:
    """
    Continuous scan; only fires on rule violations (not OK behaviour).
    """

    def __init__(
        self,
        model_path: str,
        *,
        classes: list[str] | None = None,
        confidence_threshold: float = 0.28,
        cooldown_seconds: float = 120.0,
        zones: list[CompactorZone] | None = None,
    ) -> None:
        self._model_path = model_path
        self._classes = classes or list(DEFAULT_CLASSES)
        self._confidence_threshold = confidence_threshold
        self._cooldown_seconds = cooldown_seconds
        self._zones = zones or [
            CompactorZone("container_A_papp", 0.0, 0.48, 0.15, 0.95),
            CompactorZone("container_B_annet", 0.52, 1.0, 0.15, 0.95),
        ]
        self._model: YOLO | None = None
        self._last_fire: dict[str, float] = {}
        self._feedback_delta = 0.0  # global from human learn labels
        self._reason_feedback: dict[str, _ReasonFeedback] = {}
        self._classes_dirty = True

    def _ensure_model(self) -> YOLO:
        if self._model is None:
            path = self._model_path
            if not Path(path).is_file():
                path = Path(path).name or "yolov8s-worldv2.pt"
            logger.info("Loading YOLO-World for sorting: %s", path)
            self._model = YOLO(path)
            self._classes_dirty = True
        if self._classes_dirty and hasattr(self._model, "set_classes"):
            self._model.set_classes(self._classes)
            self._classes_dirty = False
        return self._model

    def apply_learn_feedback(self, labels: list[dict]) -> None:
        """Juster terskel per årsak/sone ut fra menneske-merking (riktig/feil)."""
        wrong = 0
        correct = 0
        by_reason: dict[str, list[str]] = {}
        for row in labels:
            lab = str(row.get("label") or "")
            if lab == "wrong":
                wrong += 1
            elif lab == "correct":
                correct += 1
            else:
                continue
            reason = str(row.get("reason") or "").strip() or "_any"
            by_reason.setdefault(reason, []).append(lab)

        # Global: flere «riktig» → hev terskel (færre falske alarmer).
        delta = 0.0
        if wrong + correct >= 3:
            delta = (correct - wrong) * 0.008
            delta = max(-0.08, min(0.08, delta))
        if abs(delta - self._feedback_delta) >= 0.005:
            logger.info(
                "Learn feedback global: correct=%d wrong=%d → conf_delta=%+.3f",
                correct,
                wrong,
                delta,
            )
        self._feedback_delta = delta

        now = time.monotonic()
        new_map: dict[str, _ReasonFeedback] = {}
        for reason, labs in by_reason.items():
            if reason == "_any":
                continue
            c = sum(1 for x in labs if x == "correct")
            w = sum(1 for x in labs if x == "wrong")
            if c + w < 2:
                continue
            # correct → hev terskel for denne årsaken; wrong → senk.
            r_delta = (c - w) * 0.015
            r_delta = max(-0.12, min(0.15, r_delta))
            suppress_until = 0.0
            # Mange «dette var riktig» på samme årsak → demp midlertidig (~10 min).
            if c >= 3 and c > w * 2:
                suppress_until = now + 600.0
            new_map[reason] = _ReasonFeedback(
                conf_delta=r_delta,
                suppress_until=suppress_until,
            )
            logger.info(
                "Learn feedback reason=%s correct=%d wrong=%d → delta=%+.3f suppress=%s",
                reason,
                c,
                w,
                r_delta,
                "yes" if suppress_until else "no",
            )
        self._reason_feedback = new_map

    def _effective_confidence(self, reason: str | None = None) -> float:
        base = self._confidence_threshold + self._feedback_delta
        if reason and reason in self._reason_feedback:
            base += self._reason_feedback[reason].conf_delta
        return max(0.12, min(0.60, base))

    def _reason_suppressed(self, reason: str) -> bool:
        fb = self._reason_feedback.get(reason)
        if fb is None:
            return False
        return time.monotonic() < fb.suppress_until

    def _min_conf_for_reason(self, reason: str) -> float:
        floor = self._effective_confidence(reason)
        if reason == "unflattened_cardboard":
            floor = max(floor, UNFLATTENED_MIN_CONF + self._feedback_delta)
            fb = self._reason_feedback.get(reason)
            if fb:
                floor = max(floor, UNFLATTENED_MIN_CONF + fb.conf_delta)
        return max(0.12, min(0.60, floor))

    def analyze_frame(self, frame: np.ndarray) -> tuple[int, list[SortingHit], list[dict]]:
        model = self._ensure_model()
        # Predict med basis-terskel; filtrér per årsak etterpå.
        results = model.predict(
            frame,
            conf=self._effective_confidence(),
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
                    "text": "Tar opp video · skanner A (papp) og B (annet)…",
                }
            ]

        xyxy = boxes.xyxy.int().cpu().tolist()
        confs = boxes.conf.float().cpu().tolist()
        clss = boxes.cls.int().cpu().tolist() if boxes.cls is not None else [0] * len(xyxy)

        for i, (coords, conf, cls_id) in enumerate(zip(xyxy, confs, clss)):
            x1, y1, x2, y2 = coords
            cx = (x1 + x2) / 2.0
            cy = (y1 + y2) / 2.0
            label = str(
                names.get(
                    cls_id,
                    self._classes[cls_id] if cls_id < len(self._classes) else "object",
                )
            )
            zone = self._zone_obj_for(cx, cy, w, h)
            if zone is None:
                continue

            objects += 1
            kind = self._material_kind(label)
            violation = self._violation_for(
                zone=zone,
                kind=kind,
                label=label,
                bbox=(x1, y1, x2, y2),
                frame_w=w,
                frame_h=h,
            )

            color = (80, 200, 120) if violation is None else (40, 80, 255)
            cv2.rectangle(annotated, (x1, y1), (x2, y2), color, 2)
            tag = violation or ("ok-flat" if kind == "cardboard" else "ok")
            cv2.putText(
                annotated,
                f"{zone.name}:{tag} {conf:.2f}",
                (x1, max(20, y1 - 8)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                color,
                2,
                cv2.LINE_AA,
            )

            if violation is None:
                continue

            if self._reason_suppressed(violation):
                continue

            if float(conf) < self._min_conf_for_reason(violation):
                continue

            key = f"{zone.name}:{violation}"
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
                    reason=violation,
                    zone=zone.name,
                    annotated_frame=annotated,
                )
            )
            feed.append(
                {
                    "id": f"hit-{zone.name}-{int(now)}-{i}",
                    "status": "violation",
                    "text": self._human_reason(zone.name, violation),
                }
            )

        if objects and not candidates:
            feed.append(
                {
                    "id": f"seen-{int(now)}",
                    "status": "ok",
                    "text": f"Ser {objects} objekt(er) — OK / cooldown",
                }
            )
        elif not objects:
            feed.append(
                {
                    "id": f"scan-{int(now)}",
                    "status": "ok",
                    "text": "Tar opp video · skanner A (papp) og B (annet)…",
                }
            )

        return objects, candidates, feed

    def _material_kind(self, label: str) -> str:
        low = label.lower()
        if any(h in low for h in STYROFOAM_HINTS):
            return "styrofoam"
        if any(h in low for h in CARDBOARD_HINTS) or "box" in low:
            return "cardboard"
        return "other"

    def _geometry_flatness(
        self,
        bbox: tuple[int, int, int, int],
        frame_w: int,
        frame_h: int,
    ) -> tuple[float, float, float, bool]:
        """Return (height_frac, aspect, area_frac, looks_flat_sheet)."""
        x1, y1, x2, y2 = bbox
        bw = max(1, x2 - x1)
        bh = max(1, y2 - y1)
        area_frac = (bw * bh) / max(1, frame_w * frame_h)
        height_frac = bh / max(1, frame_h)
        aspect = bh / max(1.0, float(bw))  # tall box > flat sheet
        # Flat sheet: wide and low — også stor areal (brettet stor papp).
        looks_flat = height_frac < 0.12 and aspect < 0.55
        # Ekstra: veldig bred relativ til høyde.
        if aspect < 0.40 and height_frac < 0.18:
            looks_flat = True
        return height_frac, aspect, area_frac, looks_flat

    def _looks_unflattened(
        self,
        label: str,
        bbox: tuple[int, int, int, int],
        frame_w: int,
        frame_h: int,
    ) -> bool:
        """Geometri først: stor men flat papp er OK (ikke ubrettet)."""
        low = label.lower()
        height_frac, aspect, area_frac, looks_flat = self._geometry_flatness(
            bbox, frame_w, frame_h
        )

        if any(h in low for h in FLAT_HINTS):
            return False

        # Flat sheet i bildet → aldri ubrettet, selv om label sier oversized/contents.
        if looks_flat:
            return False

        bulky_label = any(h in low for h in BULKY_HINTS)
        # Stående / 3D: høy i bildet eller mer kvadratisk/høy.
        looks_3d = height_frac >= 0.14 or aspect >= 0.70
        if bulky_label and looks_3d:
            return True
        if looks_3d and area_frac >= 0.03:
            return True
        # Tydelig stående eske uten flat-geometri.
        if height_frac >= 0.18 and aspect >= 0.55:
            return True
        return False

    def _violation_for(
        self,
        *,
        zone: CompactorZone,
        kind: str,
        label: str,
        bbox: tuple[int, int, int, int],
        frame_w: int,
        frame_h: int,
    ) -> str | None:
        # A = papp: only unflattened cardboard is bad. Styrofoam in A also wrong.
        if zone.is_papp_zone or (
            not zone.is_annet_zone and "1" in zone.name and "2" not in zone.name
        ):
            if kind == "styrofoam":
                return "wrong_material_in_papp"
            if kind == "cardboard":
                if self._looks_unflattened(label, bbox, frame_w, frame_h):
                    return "unflattened_cardboard"
                return None
            return None

        # B = annet: styrofoam OK. Cardboard box here = bad.
        if zone.is_annet_zone or "2" in zone.name:
            if kind == "styrofoam":
                return None
            if kind == "cardboard":
                return "cardboard_in_wrong_bin"
            return None

        return None

    @staticmethod
    def _human_reason(zone: str, reason: str) -> str:
        if reason == "unflattened_cardboard":
            return f"{zone}: ubrettet/stor eske i papp-container"
        if reason == "cardboard_in_wrong_bin":
            return f"{zone}: eske kastet i annet-container (skal tømmes + brettes til A)"
        if reason == "wrong_material_in_papp":
            return f"{zone}: isopor/annet i papp-container"
        return f"{zone}: {reason}"

    def _zone_obj_for(self, cx: float, cy: float, w: int, h: int) -> CompactorZone | None:
        for z in self._zones:
            if z.contains_center(cx, cy, w, h):
                return z
        return None

    def _draw_zones(self, frame: np.ndarray, w: int, h: int) -> None:
        for z in self._zones:
            x1 = int(z.x0 * w)
            x2 = int(z.x1 * w)
            y1 = int(z.y0 * h)
            y2 = int(z.y1 * h)
            color = (60, 180, 255) if z.is_papp_zone else (200, 160, 60)
            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
            title = "A papp (brettet)" if z.is_papp_zone else "B annet (isopor OK)"
            if not z.is_papp_zone and not z.is_annet_zone:
                title = z.name
            cv2.putText(
                frame,
                title,
                (x1 + 8, y1 + 24),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.65,
                color,
                2,
                cv2.LINE_AA,
            )

    @staticmethod
    def crop_person(frame: np.ndarray, detection: SortingHit, *, padding: float = 0.08) -> np.ndarray:
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
