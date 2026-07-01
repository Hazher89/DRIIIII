"""Async Supabase REST client for vision incident rows."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

import httpx

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class VisionEventRecord:
    company_id: str
    camera_id: str
    event_type: str
    status: str
    dropbox_image_url: str
    dropbox_path: str
    timestamp: datetime
    metadata: dict[str, Any] | None = None

    def to_row(self) -> dict[str, Any]:
        row: dict[str, Any] = {
            "company_id": self.company_id,
            "camera_id": self.camera_id,
            "event_type": self.event_type,
            "status": self.status,
            "dropbox_image_url": self.dropbox_image_url,
            "dropbox_path": self.dropbox_path,
            "occurred_at": self.timestamp.astimezone(timezone.utc).isoformat(),
        }
        if self.metadata:
            row["metadata"] = self.metadata
        return row


class VisionEventRepository:
    """Writes vision events to public.vision_events via Supabase PostgREST."""

    def __init__(self, supabase_url: str, service_role_key: str) -> None:
        self._base = f"{supabase_url.rstrip('/')}/rest/v1/vision_events"
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        }

    async def insert(self, event: VisionEventRecord) -> dict[str, Any]:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                self._base,
                headers=self._headers,
                json=event.to_row(),
            )
            if response.status_code >= 400:
                logger.error("Supabase insert failed: %s %s", response.status_code, response.text)
                response.raise_for_status()

            data = response.json()
            if isinstance(data, list) and data:
                return data[0]
            return data

    async def health_check(self) -> bool:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(
                f"{self._base}?select=id&limit=1",
                headers=self._headers,
            )
            return response.status_code < 500
