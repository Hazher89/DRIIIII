"""Write browser-playable MP4 clips (H.264) from buffered JPEG frames."""

from __future__ import annotations

import logging
import subprocess
from pathlib import Path

import cv2
import numpy as np

from frame_ring_buffer import BufferedFrame

logger = logging.getLogger(__name__)


def _even(n: int) -> int:
    return n if n % 2 == 0 else n + 1


def write_clip_mp4(
    frames: list[BufferedFrame],
    path: Path,
    *,
    fps: float = 2.0,
) -> Path:
    """Write H.264 MP4 (yuv420p + faststart) so Chrome/Safari/Flutter web can play it.

    OpenCV ``mp4v`` is NOT browser-compatible (MEDIA_ERR_SRC_NOT_SUPPORTED).
    """
    if not frames:
        raise ValueError("No frames to write")

    path.parent.mkdir(parents=True, exist_ok=True)
    out_path = path.with_suffix(".mp4")
    width = _even(frames[0].width)
    height = _even(frames[0].height)

    # Never fall back to OpenCV mp4v — Chrome/Flutter web cannot play it
    # (MEDIA_ERR_SRC_NOT_SUPPORTED). Fail loud so the worker log shows the issue.
    return _write_h264_ffmpeg(frames, out_path, fps=fps, width=width, height=height)


def _ffmpeg_exe() -> str:
    try:
        import imageio_ffmpeg

        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        pass
    import shutil

    which = shutil.which("ffmpeg")
    if which:
        return which
    raise RuntimeError("imageio-ffmpeg mangler — pip install imageio-ffmpeg")


def _write_h264_ffmpeg(
    frames: list[BufferedFrame],
    out_path: Path,
    *,
    fps: float,
    width: int,
    height: int,
) -> Path:
    ffmpeg = _ffmpeg_exe()
    cmd = [
        ffmpeg,
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-f",
        "rawvideo",
        "-pix_fmt",
        "bgr24",
        "-s",
        f"{width}x{height}",
        "-r",
        str(max(0.5, fps)),
        "-i",
        "-",
        "-an",
        "-c:v",
        "libx264",
        "-preset",
        "veryfast",
        "-crf",
        "23",
        "-pix_fmt",
        "yuv420p",
        "-movflags",
        "+faststart",
        str(out_path),
    ]
    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    assert proc.stdin is not None
    written = 0
    try:
        for item in frames:
            arr = np.frombuffer(item.jpeg, dtype=np.uint8)
            img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
            if img is None:
                continue
            if img.shape[1] != width or img.shape[0] != height:
                img = cv2.resize(img, (width, height))
            proc.stdin.write(img.tobytes())
            written += 1
        proc.stdin.close()
        stderr = proc.stderr.read() if proc.stderr else b""
        code = proc.wait(timeout=120)
        if code != 0 or written < 2:
            raise RuntimeError(
                f"ffmpeg exit {code}, frames={written}, err={stderr.decode(errors='replace')[:300]}"
            )
    except Exception:
        try:
            proc.kill()
        except Exception:  # noqa: BLE001
            pass
        raise

    logger.info("Wrote H.264 clip %s (%d frames)", out_path, written)
    return out_path


def _write_opencv_fallback(
    frames: list[BufferedFrame],
    out_path: Path,
    *,
    fps: float,
    width: int,
    height: int,
) -> Path:
    """Last resort — may not play in browsers."""
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(out_path), fourcc, fps, (width, height))
    if not writer.isOpened():
        raise RuntimeError(f"Could not open VideoWriter for {out_path}")
    count = 0
    try:
        for item in frames:
            arr = np.frombuffer(item.jpeg, dtype=np.uint8)
            img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
            if img is None:
                continue
            if img.shape[1] != width or img.shape[0] != height:
                img = cv2.resize(img, (width, height))
            writer.write(img)
            count += 1
    finally:
        writer.release()
    logger.warning(
        "Wrote OpenCV mp4v clip %s (%d frames) — browsers may not play this",
        out_path,
        count,
    )
    return out_path
