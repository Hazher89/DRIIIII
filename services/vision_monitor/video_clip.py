"""Write MP4 clips from buffered JPEG frames."""

from __future__ import annotations

import logging
from pathlib import Path

import cv2
import numpy as np

from frame_ring_buffer import BufferedFrame

logger = logging.getLogger(__name__)


def write_clip_mp4(
    frames: list[BufferedFrame],
    path: Path,
    *,
    fps: float = 2.0,
) -> Path:
    if not frames:
        raise ValueError("No frames to write")

    path.parent.mkdir(parents=True, exist_ok=True)
    width = frames[0].width
    height = frames[0].height

    # Prefer mp4v; fall back to avi/XVID if needed.
    writers = [
        (path.with_suffix(".mp4"), "mp4v"),
        (path.with_suffix(".avi"), "XVID"),
    ]

    last_err: Exception | None = None
    for out_path, fourcc_name in writers:
        fourcc = cv2.VideoWriter_fourcc(*fourcc_name)
        writer = cv2.VideoWriter(str(out_path), fourcc, fps, (width, height))
        if not writer.isOpened():
            last_err = RuntimeError(f"Could not open VideoWriter for {out_path}")
            continue
        try:
            for item in frames:
                arr = np.frombuffer(item.jpeg, dtype=np.uint8)
                img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
                if img is None:
                    continue
                if img.shape[1] != width or img.shape[0] != height:
                    img = cv2.resize(img, (width, height))
                writer.write(img)
            writer.release()
            logger.info("Wrote clip %s (%d frames)", out_path, len(frames))
            return out_path
        except Exception as exc:  # noqa: BLE001
            writer.release()
            last_err = exc
            continue

    raise RuntimeError(f"Failed to write video clip: {last_err}")
