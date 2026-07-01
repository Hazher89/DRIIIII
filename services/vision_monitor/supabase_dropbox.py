"""Upload violation snapshots via DriftPro Dropbox OAuth (edge function)."""

from __future__ import annotations

import base64
import logging
from dataclasses import dataclass
from datetime import datetime, timezone

import httpx

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class DropboxUploadResult:
    path: str
    share_url: str


class SupabaseDropboxUpload:
    """Uses vision-camera edge function with service role → company Dropbox."""

    def __init__(self, supabase_url: str, service_role_key: str) -> None:
        base = supabase_url.rstrip("/")
        self._upload_url = f"{base}/functions/v1/vision-camera?action=upload"
        self._headers = {
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        }

    def upload_jpeg(
        self,
        *,
        image_bytes: bytes,
        company_id: str,
        camera_id: str,
        event_type: str,
        captured_at: datetime,
    ) -> DropboxUploadResult:
        stamp = captured_at.astimezone(timezone.utc).strftime("%Y%m%d_%H%M%S")
        file_name = f"{event_type}_{camera_id}_{stamp}.jpg"

        payload = {
            "company_id": company_id,
            "file_name": file_name,
            "bytes_base64": base64.b64encode(image_bytes).decode("ascii"),
        }

        with httpx.Client(timeout=60.0) as client:
            response = client.post(self._upload_url, headers=self._headers, json=payload)
            if response.status_code >= 400:
                logger.error("Dropbox upload failed: %s %s", response.status_code, response.text[:300])
                response.raise_for_status()
            data = response.json()

        link = data.get("temporary_link") or data.get("temporaryLink") or ""
        path = data.get("path") or ""
        if not path:
            raise RuntimeError("Dropbox upload mangler path i svar")

        return DropboxUploadResult(path=path, share_url=link)
