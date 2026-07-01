"""MAVI brystlogo — ORB-features, farge og mal på venstre bryst."""

from __future__ import annotations

import logging
from pathlib import Path

import cv2
import numpy as np

logger = logging.getLogger(__name__)


class MaviLogoMatcher:
    """Gjenkjenner MAVI-logo på venstre bryst (mørkt plagg + teal/hvit emblem)."""

    def __init__(self, template_path: Path, *, match_threshold: float = 0.38) -> None:
        self._threshold = match_threshold
        self._orb = cv2.ORB_create(nfeatures=900)
        self._bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=False)
        self._templates_gray: list[np.ndarray] = []
        self._template_kps: list = []
        self._template_desc: list[np.ndarray | None] = []
        self._load_templates(template_path)

    def _load_templates(self, path: Path) -> None:
        if not path.is_file():
            logger.warning("MAVI logo template missing at %s", path)
            return

        img = cv2.imread(str(path), cv2.IMREAD_COLOR)
        if img is None:
            return

        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        h, w = gray.shape[:2]
        # Bruk primært ikon-delen (øverst) — ikke hele «Logistikk AS»-teksten.
        icon = gray[: max(24, int(h * 0.62)), :]
        for scale in (0.4, 0.55, 0.75, 1.0, 1.25, 1.6):
            tw = max(28, int(icon.shape[1] * scale))
            th = max(28, int(icon.shape[0] * scale))
            tmpl = cv2.resize(icon, (tw, th), interpolation=cv2.INTER_AREA)
            kp, desc = self._orb.detectAndCompute(tmpl, None)
            self._templates_gray.append(tmpl)
            self._template_kps.append(kp or [])
            self._template_desc.append(desc)

        logger.info("MAVI logo matcher: %s skalaer fra %s", len(self._templates_gray), path)

    def score(self, frame: np.ndarray, bbox: tuple[int, int, int, int]) -> tuple[bool, float]:
        """Returnerer (mangler_logo, logo_score 0–1)."""
        roi = self._left_chest_roi(frame, bbox)
        if roi is None or roi.size == 0:
            return False, 1.0

        orb_score = self._orb_score(roi)
        color_score = self._brand_color_score(roi)
        template_score = self._template_score(roi)
        combined = max(orb_score, color_score * 0.95, template_score * 0.85)

        missing = combined < self._threshold
        return missing, float(combined)

    @staticmethod
    def _left_chest_roi(
        frame: np.ndarray, bbox: tuple[int, int, int, int]
    ) -> np.ndarray | None:
        x1, y1, x2, y2 = bbox
        h, w = frame.shape[:2]
        bw, bh = x2 - x1, y2 - y1
        if bw < 40 or bh < 80:
            return None

        # Logo sitter på personens venstre bryst (venstre side i bildet når de vender seg mot kamera).
        chest_y1 = y1 + int(bh * 0.14)
        chest_y2 = y1 + int(bh * 0.46)
        chest_x1 = x1 + int(bw * 0.04)
        chest_x2 = x1 + int(bw * 0.44)
        chest_y1, chest_y2 = max(0, chest_y1), min(h, chest_y2)
        chest_x1, chest_x2 = max(0, chest_x1), min(w, chest_x2)
        if chest_x2 - chest_x1 < 24 or chest_y2 - chest_y1 < 24:
            return None
        return frame[chest_y1:chest_y2, chest_x1:chest_x2]

    def _orb_score(self, roi: np.ndarray) -> float:
        if not self._template_desc:
            return 0.0

        gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
        gray = cv2.equalizeHist(gray)
        kp_roi, desc_roi = self._orb.detectAndCompute(gray, None)
        if desc_roi is None or len(kp_roi) < 6:
            return 0.0

        best_ratio = 0.0
        for tpl_desc in self._template_desc:
            if tpl_desc is None or len(tpl_desc) < 4:
                continue
            matches = self._bf.knnMatch(tpl_desc, desc_roi, k=2)
            good = 0
            for pair in matches:
                if len(pair) < 2:
                    continue
                m, n = pair
                if m.distance < 0.72 * n.distance:
                    good += 1
            ratio = good / max(1, len(matches))
            best_ratio = max(best_ratio, ratio)

        return min(1.0, best_ratio * 2.2)

    @staticmethod
    def _brand_color_score(roi: np.ndarray) -> float:
        """Teal/hvit MAVI-emblem på mørkt plagg."""
        hsv = cv2.cvtColor(roi, cv2.COLOR_BGR2HSV)
        teal = cv2.inRange(hsv, (78, 35, 35), (102, 255, 255))
        white = cv2.inRange(hsv, (0, 0, 165), (180, 70, 255))
        area = max(1, roi.shape[0] * roi.shape[1])
        teal_r = float(np.count_nonzero(teal)) / area
        white_r = float(np.count_nonzero(white)) / area

        # Mørkt plagg rundt logo gir høyere tillit.
        gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
        dark_r = float(np.mean(gray < 95))

        score = teal_r * 14.0 + white_r * 6.0
        if dark_r > 0.25:
            score *= 1.15
        return min(1.0, score)

    def _template_score(self, roi: np.ndarray) -> float:
        if not self._templates_gray:
            return 0.0
        gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
        gray = cv2.equalizeHist(gray)
        best = 0.0
        for tmpl in self._templates_gray:
            th, tw = tmpl.shape[:2]
            if gray.shape[0] < th + 4 or gray.shape[1] < tw + 4:
                continue
            res = cv2.matchTemplate(gray, tmpl, cv2.TM_CCOEFF_NORMED)
            _, max_val, _, _ = cv2.minMaxLoc(res)
            best = max(best, float(max_val))
        return best
