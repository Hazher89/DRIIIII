"""IP camera capture — HTTP snapshot, MJPEG, or RTSP via OpenCV."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from urllib.parse import urljoin, urlparse

import cv2
import httpx
import numpy as np

from config import CameraMode, Settings

logger = logging.getLogger(__name__)


@dataclass
class FramePacket:
    frame: np.ndarray
    frame_index: int
    source_url: str


# Common paths for ONVIF / Hikvision-style cameras (gSOAP server).
SNAPSHOT_CANDIDATES = [
    "/ISAPI/Streaming/channels/101/picture",
    "/ISAPI/Streaming/channels/1/picture",
    "/cgi-bin/snapshot.cgi?channel=1",
    "/tmpfs/auto.jpg",
    "/onvif-http/snapshot?Profile_1",
    "/jpg/image.jpg",
]

STREAM_CANDIDATES = [
    "/Streaming/Channels/101",
    "/h264/ch1/main/av_stream",
    "/stream1",
    "/live/ch00_0",
    "/video.mjpg",
    "/cgi-bin/mjpg/video.cgi",
]


class IpCamera:
    """Blocking camera reader — run inside asyncio.to_thread."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._cap: cv2.VideoCapture | None = None
        self._frame_index = 0
        self._active_url = settings.camera_url
        self._mode: CameraMode = settings.camera_mode
        self._client: httpx.Client | None = None
        self._auth: httpx.DigestAuth | httpx.BasicAuth | None = None
        self._last_snapshot: bytes | None = None
        self._stale_snapshots = 0

    def open(self) -> None:
        if self._settings.camera_user:
            self._auth = httpx.DigestAuth(
                self._settings.camera_user,
                self._settings.camera_password,
            )

        if self._mode == CameraMode.AUTO:
            self._mode = self._discover_mode()

        if self._mode == CameraMode.SNAPSHOT:
            self._client = httpx.Client(timeout=10.0, follow_redirects=True)
            logger.info("Camera mode=snapshot url=%s", self._active_url)
            frame = self._read_snapshot()
            if frame is None:
                raise RuntimeError(
                    f"Could not read snapshot from {self._active_url}. "
                    "Set CAMERA_USER and CAMERA_PASSWORD in .env"
                )
            return

        logger.info("Camera mode=stream url=%s", self._mask_url(self._active_url))
        cap = cv2.VideoCapture(self._active_url, cv2.CAP_FFMPEG)
        cap.set(cv2.CAP_PROP_BUFFERSIZE, 2)
        if not cap.isOpened():
            raise RuntimeError(f"Could not open camera stream: {self._mask_url(self._active_url)}")
        self._cap = cap

    def read(self) -> FramePacket | None:
        if self._mode == CameraMode.SNAPSHOT:
            time.sleep(self._settings.snapshot_interval_ms / 1000.0)
            frame = self._read_snapshot()
        else:
            if self._cap is None:
                raise RuntimeError("Camera not opened")
            ok, frame = self._cap.read()
            if not ok or frame is None:
                return None

        if frame is None:
            return None

        self._frame_index += 1
        return FramePacket(
            frame=frame,
            frame_index=self._frame_index,
            source_url=self._active_url,
        )

    def close(self) -> None:
        if self._cap is not None:
            self._cap.release()
            self._cap = None
        if self._client is not None:
            self._client.close()
            self._client = None

    def _discover_mode(self) -> CameraMode:
        base = self._base_http_url()
        logger.info("Auto-discovering camera at %s", base)

        if self._settings.camera_url.startswith("rtsp://"):
            self._active_url = self._settings.camera_url
            return CameraMode.STREAM

        onvif_rtsp = self._discover_onvif_rtsp()
        if onvif_rtsp:
            self._active_url = onvif_rtsp
            logger.info("ONVIF live stream: %s", self._mask_url(onvif_rtsp))
            return CameraMode.STREAM

        for path in STREAM_CANDIDATES:
            http_url = self._build_http_stream_url(path)
            if self._probe_stream_live(http_url):
                self._active_url = http_url
                return CameraMode.STREAM
            rtsp_url = self._build_rtsp_url(path)
            if self._probe_stream_live(rtsp_url):
                self._active_url = rtsp_url
                return CameraMode.STREAM

        rtsp = self._build_rtsp_url("/Streaming/Channels/101")
        if self._probe_stream_live(rtsp):
            self._active_url = rtsp
            return CameraMode.STREAM

        for path in SNAPSHOT_CANDIDATES:
            url = urljoin(base, path.lstrip("/"))
            if self._probe_snapshot(url):
                self._active_url = url
                logger.warning(
                    "Using HTTP snapshot (not live video): %s — ONVIF/RTSP unavailable",
                    url,
                )
                return CameraMode.SNAPSHOT

        self._active_url = urljoin(base, SNAPSHOT_CANDIDATES[0].lstrip("/"))
        logger.warning("Discovery failed — defaulting to snapshot mode: %s", self._active_url)
        return CameraMode.SNAPSHOT

    def _discover_onvif_rtsp(self) -> str | None:
        """ONVIF GetStreamUri — finner ekte RTSP live på mange IP-kameraer."""
        try:
            from onvif import ONVIFCamera
        except ImportError:
            logger.debug("onvif-zeep not installed — skip ONVIF discovery")
            return None

        host = self._settings.camera_host
        port = 80
        parsed = urlparse(self._settings.camera_url)
        if parsed.port:
            port = parsed.port

        try:
            cam = ONVIFCamera(
                host,
                port,
                self._settings.camera_user,
                self._settings.camera_password,
            )
            media = cam.create_media_service()
            for profile in media.GetProfiles():
                uri = media.GetStreamUri(
                    {
                        "StreamSetup": {
                            "Stream": "RTP-Unicast",
                            "Transport": {"Protocol": "RTSP"},
                        },
                        "ProfileToken": profile.token,
                    }
                )
                rtsp = self._inject_rtsp_auth(uri.Uri)
                if self._probe_stream_live(rtsp):
                    return rtsp
        except Exception as exc:
            logger.debug("ONVIF discovery failed: %s", exc)
        return None

    def _inject_rtsp_auth(self, url: str) -> str:
        if "@" in url or not self._settings.camera_user:
            return url
        parsed = urlparse(url)
        auth = f"{self._settings.camera_user}:{self._settings.camera_password}@"
        host = parsed.hostname or self._settings.camera_host
        port = parsed.port or 554
        path = parsed.path or "/"
        return f"rtsp://{auth}{host}:{port}{path}"

    def _base_http_url(self) -> str:
        parsed = urlparse(self._settings.camera_url)
        if parsed.scheme in {"http", "https"} and parsed.netloc:
            return f"{parsed.scheme}://{parsed.netloc}/"
        return f"http://{self._settings.camera_host}/"

    def _build_rtsp_url(self, path: str) -> str:
        user = self._settings.camera_user
        password = self._settings.camera_password
        host = self._settings.camera_host
        auth = f"{user}:{password}@" if user else ""
        return f"rtsp://{auth}{host}:554{path}"

    def _build_http_stream_url(self, path: str) -> str:
        base = self._base_http_url().rstrip("/")
        return f"{base}{path}"

    def _probe_snapshot(self, url: str) -> bool:
        try:
            with httpx.Client(timeout=5.0, follow_redirects=True) as client:
                response = client.get(url, auth=self._auth)
                if response.status_code != 200:
                    return False
                if len(response.content) < 1000:
                    return False
                if response.content[:2] == b"\xff\xd8":
                    return True
                return response.headers.get("content-type", "").startswith("image/")
        except Exception:
            return False

    def _probe_stream(self, url: str) -> bool:
        return self._probe_stream_live(url)

    def _probe_stream_live(self, url: str) -> bool:
        import hashlib

        cap = cv2.VideoCapture(url, cv2.CAP_FFMPEG)
        try:
            if not cap.isOpened():
                return False
            hashes: set[str] = set()
            for _ in range(8):
                ok, frame = cap.read()
                if not ok or frame is None:
                    return False
                hashes.add(hashlib.md5(frame.tobytes()).hexdigest())
            return len(hashes) > 1
        except Exception:
            return False
        finally:
            cap.release()

    def _read_snapshot(self) -> np.ndarray | None:
        if self._client is None:
            self._client = httpx.Client(timeout=10.0, follow_redirects=True)

        try:
            sep = "&" if "?" in self._active_url else "?"
            url = f"{self._active_url}{sep}_t={int(time.time() * 1000)}"
            response = self._client.get(url, auth=self._auth)
            if response.status_code != 200 or len(response.content) < 500:
                return None
            if response.content[:2] != b"\xff\xd8" and not response.headers.get(
                "content-type", ""
            ).startswith("image/"):
                return None
            if response.content == self._last_snapshot:
                self._stale_snapshots += 1
                if self._stale_snapshots == 30:
                    logger.warning(
                        "Camera snapshot unchanged for 30 reads — only still images available. "
                        "Set CAMERA_MODE=stream and CAMERA_URL=rtsp://... for live video."
                    )
            else:
                self._stale_snapshots = 0
                self._last_snapshot = response.content
            arr = np.frombuffer(response.content, dtype=np.uint8)
            frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
            return frame
        except Exception as exc:
            logger.debug("Snapshot read failed: %s", exc)
            return None

    @staticmethod
    def _mask_url(url: str) -> str:
        if "@" not in url:
            return url
        prefix, suffix = url.split("@", 1)
        if "://" in prefix:
            scheme, _ = prefix.split("://", 1)
            return f"{scheme}://***@{suffix}"
        return f"***@{suffix}"


def encode_jpeg(frame: np.ndarray, quality: int) -> bytes:
    ok, encoded = cv2.imencode(
        ".jpg",
        frame,
        [int(cv2.IMWRITE_JPEG_QUALITY), quality],
    )
    if not ok:
        raise RuntimeError("Failed to encode JPEG snapshot")
    return encoded.tobytes()
