"""Detect bad waste sorting at two compactors (YOLO-World, offline).

MAVI workflow (normal — NOT a violation):
  1) Driver dumps everything into B (stairs / annet) first.
  2) Moves flattened cardboard to A (wall / papp).
  Temporary cardboard in B while working = OK.
  Angled/stacked flat sheets in A look 3D from this camera — NOT a violation.

This camera angle cannot reliably see «brettet vs ubrettet».
Auto-save only clear faults:
  - Styrofoam / trash bags / mixed waste inside A (papp)
  - (Optional, rare) sealed full box with contents in A at very high conf

Cardboard shape / «left in B» is NOT auto-flagged (too many false positives).
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

# Viktig: IKKE ha «tall/standing/unflattened box»-klasser.
# Ovenfra matcher YOLO dem mot vanlig brettet papp → masse falske avvik.
DEFAULT_CLASSES = [
    "flat brown cardboard sheet",
    "flattened cardboard in dumpster",
    "pile of flat cardboard",
    "white styrofoam block",
    "expanded polystyrene foam packing",
    "foam packaging material",
    "black garbage bag",
    "plastic trash bag",
    "mixed waste garbage pile",
    "sealed cardboard box full of items",
]

STYROFOAM_HINTS = (
    "styrofoam",
    "polystyrene",
    "foam",
    "isopor",
    "eps",
)

BAG_TRASH_HINTS = (
    "garbage bag",
    "trash bag",
    "plastic bag",
    "mixed waste",
    "garbage pile",
    "garbage",
)

CARDBOARD_HINTS = (
    "cardboard",
    "carton",
    "corrugated",
)

CONTENTS_HINTS = (
    "full of items",
    "sealed cardboard box full",
    "contents",
)

# A-side faults we may auto-save (shape-based unflattened is OFF).
A_SIDE_REASONS = frozenset(
    {
        "wrong_material_in_papp",
        "box_with_contents",
    }
)

WRONG_MATERIAL_MIN_CONF = 0.35
BOX_CONTENTS_MIN_CONF = 0.72


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
    reason: str
    zone: str
    annotated_frame: np.ndarray


@dataclass
class _ReasonFeedback:
    conf_delta: float = 0.0
    suppress_until: float = 0.0


class SortingDetector:
    """Conservative detector — prefer miss over false alarm."""

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
        self._feedback_delta = 0.0
        self._reason_feedback: dict[str, _ReasonFeedback] = {}
        self._extra_flat_hints: set[str] = set()
        self._extra_bulky_hints: set[str] = set()
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
            logger.info("YOLO classes (conservative): %s", self._classes)
        return self._model

    def apply_learn_feedback(self, labels: list[dict]) -> None:
        """Soft threshold tweak from human labels — never hard-suppress."""
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

        delta = 0.0
        if wrong + correct >= 3:
            delta = (correct - wrong) * 0.008
            delta = max(-0.08, min(0.08, delta))
        self._feedback_delta = delta

        new_map: dict[str, _ReasonFeedback] = {}
        for reason, labs in by_reason.items():
            if reason == "_any":
                continue
            c = sum(1 for x in labs if x == "correct")
            w = sum(1 for x in labs if x == "wrong")
            if c + w < 1:
                continue
            r_delta = (c - w) * 0.012
            r_delta = max(-0.10, min(0.10, r_delta))
            new_map[reason] = _ReasonFeedback(conf_delta=r_delta, suppress_until=0.0)
        self._reason_feedback = new_map
        if by_reason:
            logger.info(
                "Learn feedback applied (soft only) global=%+.3f reasons=%d",
                delta,
                len(new_map),
            )

    def _effective_confidence(self, reason: str | None = None) -> float:
        base = self._confidence_threshold + self._feedback_delta
        if reason and reason in self._reason_feedback:
            base += self._reason_feedback[reason].conf_delta
        return max(0.12, min(0.55, base))

    def _reason_suppressed(self, reason: str) -> bool:
        return False

    def _min_conf_for_reason(self, reason: str) -> float:
        floor = self._effective_confidence(reason)
        if reason == "wrong_material_in_papp":
            floor = max(floor, WRONG_MATERIAL_MIN_CONF)
        if reason == "box_with_contents":
            floor = max(floor, BOX_CONTENTS_MIN_CONF)
        fb = self._reason_feedback.get(reason)
        if fb:
            floor += fb.conf_delta
        return max(0.12, min(0.80, floor))

    def analyze_frame(
        self,
        frame: np.ndarray,
        *,
        end_of_visit: bool = False,
    ) -> tuple[int, list[SortingHit], list[dict]]:
        """Scan for clear faults only. Cardboard shape is never auto-flagged."""
        model = self._ensure_model()
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
                    "text": (
                        "Sluttvurdering: ingen tydelig feil"
                        if end_of_visit
                        else "Skanner — papp i A / midlertidig i B = OK"
                    ),
                }
            ]

        xyxy = boxes.xyxy.int().cpu().tolist()
        confs = boxes.conf.float().cpu().tolist()
        clss = (
            boxes.cls.int().cpu().tolist() if boxes.cls is not None else [0] * len(xyxy)
        )

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
                end_of_visit=end_of_visit,
            )

            color = (80, 200, 120) if violation is None else (40, 80, 255)
            cv2.rectangle(annotated, (x1, y1), (x2, y2), color, 2)
            tag = violation or ("ok" if kind == "cardboard" else kind)
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

            min_conf = self._min_conf_for_reason(violation)
            if float(conf) < min_conf:
                skip_key = f"skip:{zone.name}:{violation}"
                if now - self._last_fire.get(skip_key, 0.0) > 30.0:
                    self._last_fire[skip_key] = now
                    logger.info(
                        "Skip %s conf=%.2f < min=%.2f",
                        violation,
                        float(conf),
                        min_conf,
                    )
                continue

            key = f"{zone.name}:{violation}"
            if not end_of_visit:
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
                    "text": (
                        "Sluttvurdering OK — papp/brettet ser vi ikke som avvik"
                        if end_of_visit
                        else f"Ser {objects} objekt(er) — OK (kun feil materiale i A lagres)"
                    ),
                }
            )

        candidates.sort(key=lambda h: -h.confidence)
        return objects, candidates, feed

    def _material_kind(self, label: str) -> str:
        low = label.lower()
        if any(h in low for h in STYROFOAM_HINTS):
            return "styrofoam"
        if any(h in low for h in BAG_TRASH_HINTS):
            return "trash"
        if any(h in low for h in CARDBOARD_HINTS) or "box" in low:
            return "cardboard"
        return "other"

    def _looks_full_box(self, label: str) -> bool:
        low = label.lower()
        return any(h in low for h in CONTENTS_HINTS)

    def _violation_for(
        self,
        *,
        zone: CompactorZone,
        kind: str,
        label: str,
        bbox: tuple[int, int, int, int],
        frame_w: int,
        frame_h: int,
        end_of_visit: bool = False,
    ) -> str | None:
        """Return violation reason or None.

        Cardboard in A or B is never a shape-based auto-fault from this camera.
        """
        _ = (bbox, frame_w, frame_h, end_of_visit)  # reserved / API stable

        if zone.is_papp_zone or (
            not zone.is_annet_zone and "1" in zone.name and "2" not in zone.name
        ):
            if kind in ("styrofoam", "trash"):
                return "wrong_material_in_papp"
            if kind == "cardboard":
                # Kameraet kan ikke skille brettet vs ubrettet sikkert.
                # Kun svært tydelig «full eske med innhold».
                if self._looks_full_box(label):
                    return "box_with_contents"
                return None
            return None

        # B = annet: styrofoam OK, cardboard temporary OK, leftover not auto-flagged.
        if zone.is_annet_zone or "2" in zone.name:
            return None

        return None

    @staticmethod
    def _human_reason(zone: str, reason: str) -> str:
        if reason == "box_with_contents":
            return f"{zone}: eske med innhold i papp-container"
        if reason == "wrong_material_in_papp":
            return f"{zone}: isopor/søppel i papp-container (kun papp)"
        if reason == "unflattened_cardboard":
            return f"{zone}: ubrettet eske (manuell vurdering)"
        if reason == "cardboard_in_wrong_bin":
            return f"{zone}: eske i annet (manuell vurdering)"
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
            title = "A papp (brettet OK)" if z.is_papp_zone else "B annet (midlertidig OK)"
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
    def crop_person(
        frame: np.ndarray, detection: SortingHit, *, padding: float = 0.08
    ) -> np.ndarray:
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
