"""Load camera definitions from Supabase for multi-camera worker."""

from __future__ import annotations

import logging
from dataclasses import dataclass

import httpx

from config import EventType, Settings

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class CameraConfig:
    camera_id: str
    camera_url: str
    camera_host: str
    camera_user: str
    camera_password: str
    event_type: EventType
    company_id: str


async def load_cameras_from_supabase(settings: Settings) -> list[CameraConfig]:
    if not settings.supabase_service_role_key:
        return []

    url = f"{settings.supabase_url}/rest/v1/rpc/list_vision_cameras_for_worker"
    headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "Content-Type": "application/json",
    }
    body = {}
    if settings.company_id and settings.company_id != "00000000-0000-0000-0000-000000000000":
        body["p_company_id"] = settings.company_id

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(url, headers=headers, json=body)
        if response.status_code >= 400:
            logger.warning("Supabase camera load failed: %s", response.text)
            return []
        rows = response.json()

    configs: list[CameraConfig] = []
    for raw in rows:
        row = raw if isinstance(raw, dict) else {}
        host = str(row.get("host", "")).strip()
        if not host:
            continue
        port = int(row.get("http_port") or 80)
        path = str(row.get("snapshot_path") or "/ISAPI/Streaming/channels/101/picture")
        base = f"http://{host}" if port == 80 else f"http://{host}:{port}"
        snap_url = f"{base}{path}"
        try:
            event_type = EventType(str(row.get("event_type") or "ppe_violation"))
        except ValueError:
            event_type = EventType.PPE_VIOLATION

        configs.append(
            CameraConfig(
                camera_id=str(row.get("id")),
                camera_url=snap_url,
                camera_host=host,
                camera_user=str(row.get("camera_user") or "admin"),
                camera_password=str(row.get("camera_password") or ""),
                event_type=event_type,
                company_id=str(row.get("company_id")),
            )
        )

    logger.info("Loaded %s cameras from Supabase", len(configs))
    return configs


def camera_config_from_env(settings: Settings) -> CameraConfig:
    return CameraConfig(
        camera_id=settings.camera_id,
        camera_url=settings.camera_url,
        camera_host=settings.camera_host,
        camera_user=settings.camera_user,
        camera_password=settings.camera_password,
        event_type=settings.event_type,
        company_id=settings.company_id,
    )
