"""Async Supabase REST client for vision incident rows + learn mode."""

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


@dataclass(frozen=True)
class LearnCameraState:
    learn_mode: bool
    learn_session_id: str | None


class VisionEventRepository:
    """Writes vision events to public.vision_events via Supabase PostgREST."""

    def __init__(self, supabase_url: str, service_role_key: str) -> None:
        self._root = supabase_url.rstrip("/")
        self._base = f"{self._root}/rest/v1/vision_events"
        self._cameras = f"{self._root}/rest/v1/vision_cameras"
        self._sessions = f"{self._root}/rest/v1/vision_learn_sessions"
        self._labels = f"{self._root}/rest/v1/vision_learn_labels"
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

    async def fetch_camera_company_id(self, camera_db_id: str) -> str | None:
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.get(
                f"{self._cameras}?id=eq.{camera_db_id}&select=company_id",
                headers=self._headers,
            )
            if response.status_code >= 400:
                return None
            rows = response.json()
            if not isinstance(rows, list) or not rows:
                return None
            cid = rows[0].get("company_id")
            return str(cid) if cid else None

    async def fetch_dropbox_company_id(self) -> str | None:
        """Første bedrift med Dropbox-kobling (unngå placeholder 00000000)."""
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.get(
                f"{self._root}/rest/v1/company_dropbox_connections"
                f"?select=company_id&limit=5",
                headers=self._headers,
            )
            if response.status_code >= 400:
                logger.warning(
                    "fetch_dropbox_company_id failed: %s %s",
                    response.status_code,
                    response.text[:200],
                )
                return None
            rows = response.json()
            if not isinstance(rows, list):
                return None
            nil = "00000000-0000-0000-0000-000000000000"
            for row in rows:
                cid = row.get("company_id")
                if cid and str(cid) != nil:
                    return str(cid)
            if rows and rows[0].get("company_id"):
                return str(rows[0]["company_id"])
            return None

    async def fetch_learn_state(self, camera_db_id: str) -> LearnCameraState | None:
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.get(
                f"{self._cameras}?id=eq.{camera_db_id}"
                f"&select=learn_mode,learn_session_id",
                headers=self._headers,
            )
            if response.status_code >= 400:
                logger.warning(
                    "fetch_learn_state failed: %s %s",
                    response.status_code,
                    response.text[:200],
                )
                return None
            rows = response.json()
            if not isinstance(rows, list) or not rows:
                return None
            row = rows[0]
            return LearnCameraState(
                learn_mode=bool(row.get("learn_mode")),
                learn_session_id=row.get("learn_session_id"),
            )

    async def patch_learn_session(
        self,
        session_id: str,
        *,
        status: str | None = None,
        dropbox_video_path: str | None = None,
        dropbox_video_url: str | None = None,
        dropbox_paths: list[str] | None = None,
        duration_seconds: float | None = None,
        chunk_count: int | None = None,
        error_message: str | None = None,
        stopped_at: datetime | None = None,
    ) -> dict[str, Any] | None:
        payload: dict[str, Any] = {
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        if status is not None:
            payload["status"] = status
        if dropbox_video_path is not None:
            payload["dropbox_video_path"] = dropbox_video_path
        if dropbox_video_url is not None:
            payload["dropbox_video_url"] = dropbox_video_url
        if dropbox_paths is not None:
            payload["dropbox_paths"] = dropbox_paths
        if duration_seconds is not None:
            payload["duration_seconds"] = duration_seconds
        if chunk_count is not None:
            payload["chunk_count"] = chunk_count
        if error_message is not None:
            payload["error_message"] = error_message
        if stopped_at is not None:
            payload["stopped_at"] = stopped_at.astimezone(timezone.utc).isoformat()

        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.patch(
                f"{self._sessions}?id=eq.{session_id}",
                headers=self._headers,
                json=payload,
            )
            if response.status_code >= 400:
                logger.error(
                    "patch_learn_session failed: %s %s",
                    response.status_code,
                    response.text[:300],
                )
                return None
            data = response.json()
            if isinstance(data, list) and data:
                return data[0]
            return data if isinstance(data, dict) else None

    async def clear_camera_learn_session(self, camera_db_id: str) -> None:
        async with httpx.AsyncClient(timeout=15.0) as client:
            await client.patch(
                f"{self._cameras}?id=eq.{camera_db_id}",
                headers=self._headers,
                json={
                    "learn_mode": False,
                    "learn_session_id": None,
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                },
            )

    async def fetch_recent_learn_labels(self, *, limit: int = 80) -> list[dict[str, Any]]:
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.get(
                f"{self._labels}?select=label,zone,reason,note,created_at"
                f"&order=created_at.desc&limit={limit}",
                headers=self._headers,
            )
            if response.status_code >= 400:
                return []
            data = response.json()
            return data if isinstance(data, list) else []
