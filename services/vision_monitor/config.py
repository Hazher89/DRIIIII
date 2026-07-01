"""Environment-driven configuration for the vision monitor service."""

from __future__ import annotations

import os
from dataclasses import dataclass
from enum import Enum

from dotenv import load_dotenv

load_dotenv()


class EventType(str, Enum):
    PPE_VIOLATION = "ppe_violation"
    UNIFORM_VIOLATION = "uniform_violation"
    PARKING_ENTRY = "parking_entry"
    PARKING_EXIT = "parking_exit"


class CameraMode(str, Enum):
    AUTO = "auto"
    STREAM = "stream"
    SNAPSHOT = "snapshot"


@dataclass(frozen=True)
class Settings:
    camera_url: str
    camera_host: str
    camera_user: str
    camera_password: str
    camera_mode: CameraMode
    camera_id: str
    company_id: str
    supabase_url: str
    supabase_service_role_key: str
    dropbox_access_token: str
    dropbox_root_folder: str
    yolo_model: str
    event_type: EventType
    confidence_threshold: float
    entry_cooldown_seconds: float
    frame_skip: int
    jpeg_quality: int
    local_dev: bool
    local_captures_dir: str
    local_server_port: int
    snapshot_interval_ms: int

    @classmethod
    def from_env(cls) -> Settings:
        event_raw = os.environ.get("EVENT_TYPE", EventType.PPE_VIOLATION.value)
        try:
            event_type = EventType(event_raw)
        except ValueError as exc:
            raise ValueError(
                f"Invalid EVENT_TYPE={event_raw!r}. "
                f"Use one of: {[e.value for e in EventType]}"
            ) from exc

        mode_raw = os.environ.get("CAMERA_MODE", CameraMode.AUTO.value)
        try:
            camera_mode = CameraMode(mode_raw)
        except ValueError as exc:
            raise ValueError(f"Invalid CAMERA_MODE={mode_raw!r}") from exc

        host = os.environ.get("CAMERA_HOST", "192.168.39.190").strip()
        camera_url = (
            os.environ.get("CAMERA_URL", "").strip()
            or os.environ.get("RTSP_URL", "").strip()
            or f"http://{host}/"
        )

        local_dev = os.environ.get("LOCAL_DEV", "true").lower() in {"1", "true", "yes"}

        return cls(
            camera_url=camera_url,
            camera_host=host,
            camera_user=os.environ.get("CAMERA_USER", "admin").strip(),
            camera_password=os.environ.get("CAMERA_PASSWORD", "").strip(),
            camera_mode=camera_mode,
            camera_id=os.environ.get("CAMERA_ID", "cam-local-01").strip(),
            company_id=os.environ.get("COMPANY_ID", "00000000-0000-0000-0000-000000000000"),
            supabase_url=os.environ.get("SUPABASE_URL", "https://ksnnyccthotjbrmgjgdc.supabase.co").rstrip("/"),
            supabase_service_role_key=os.environ.get("SUPABASE_SERVICE_ROLE_KEY", ""),
            dropbox_access_token=os.environ.get("DROPBOX_ACCESS_TOKEN", ""),
            dropbox_root_folder=os.environ.get("DROPBOX_ROOT_FOLDER", "/DriftPro/vision").rstrip("/"),
            yolo_model=os.environ.get("YOLO_MODEL", "models/yolov8n.pt"),
            event_type=event_type,
            confidence_threshold=float(os.environ.get("CONFIDENCE_THRESHOLD", "0.45")),
            entry_cooldown_seconds=float(os.environ.get("ENTRY_COOLDOWN_SECONDS", "8")),
            frame_skip=max(1, int(os.environ.get("FRAME_SKIP", "2"))),
            jpeg_quality=min(100, max(50, int(os.environ.get("JPEG_QUALITY", "92")))),
            local_dev=local_dev,
            local_captures_dir=os.environ.get("LOCAL_CAPTURES_DIR", "captures").strip(),
            local_server_port=int(os.environ.get("LOCAL_SERVER_PORT", "8090")),
            snapshot_interval_ms=int(os.environ.get("SNAPSHOT_INTERVAL_MS", "250")),
        )
