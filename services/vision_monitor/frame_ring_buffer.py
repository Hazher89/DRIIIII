"""Ring buffer of recent camera frames for pre/post event video clips."""

from __future__ import annotations

import time
from collections import deque
from dataclasses import dataclass

import cv2
import numpy as np


@dataclass(frozen=True)
class BufferedFrame:
    t: float
    jpeg: bytes
    width: int
    height: int


class FrameRingBuffer:
    """Keep the last ``seconds`` of JPEG frames (memory-friendly)."""

    def __init__(self, *, seconds: float = 60.0, target_fps: float = 2.0) -> None:
        self._seconds = max(5.0, seconds)
        self._min_interval = 1.0 / max(0.5, target_fps)
        self._frames: deque[BufferedFrame] = deque()
        self._last_push = 0.0

    def push(self, frame: np.ndarray, *, quality: int = 70) -> None:
        now = time.monotonic()
        if now - self._last_push < self._min_interval:
            return
        self._last_push = now
        h, w = frame.shape[:2]
        ok, encoded = cv2.imencode(
            ".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), quality]
        )
        if not ok:
            return
        self._frames.append(
            BufferedFrame(t=now, jpeg=encoded.tobytes(), width=w, height=h)
        )
        cutoff = now - self._seconds
        while self._frames and self._frames[0].t < cutoff:
            self._frames.popleft()

    def snapshot(self) -> list[BufferedFrame]:
        return list(self._frames)

    def clear(self) -> None:
        self._frames.clear()
