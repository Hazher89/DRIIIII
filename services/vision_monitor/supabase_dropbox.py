"""Upload violation snapshots via DriftPro Dropbox OAuth (edge function).

Small files go through edge as base64. Large MP4s upload directly to Dropbox
using a short-lived token from action=dropbox_auth (avoids WORKER_RESOURCE_LIMIT).
"""

from __future__ import annotations

import base64
import logging
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import httpx

logger = logging.getLogger(__name__)

# Edge base64 upload blows memory around ~4-8MB decoded; stay under.
_EDGE_MAX_BYTES = 3_500_000
_DROPBOX_SIMPLE_MAX = 140 * 1024 * 1024  # Dropbox simple upload limit ~150MB


@dataclass(frozen=True)
class DropboxUploadResult:
    path: str
    share_url: str


class SupabaseDropboxUpload:
    """Uses vision-camera edge function with service role → company Dropbox."""

    def __init__(self, supabase_url: str, service_role_key: str) -> None:
        base = supabase_url.rstrip("/")
        self._base = base
        self._upload_url = f"{base}/functions/v1/vision-camera?action=upload"
        self._auth_url = f"{base}/functions/v1/vision-camera?action=dropbox_auth"
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
        return self.upload_file(
            data=image_bytes,
            company_id=company_id,
            file_name=file_name,
            category="vision_uniform",
        )

    def upload_file(
        self,
        *,
        data: bytes,
        company_id: str,
        file_name: str,
        category: str = "vision_sorting_clip",
    ) -> DropboxUploadResult:
        if len(data) <= _EDGE_MAX_BYTES:
            return self._upload_via_edge(
                data=data,
                company_id=company_id,
                file_name=file_name,
                category=category,
            )
        logger.info(
            "Large file (%d bytes) — direct Dropbox upload via dropbox_auth",
            len(data),
        )
        return self._upload_direct(
            data=data,
            company_id=company_id,
            file_name=file_name,
            category=category,
        )

    def _upload_via_edge(
        self,
        *,
        data: bytes,
        company_id: str,
        file_name: str,
        category: str,
    ) -> DropboxUploadResult:
        payload = {
            "company_id": company_id,
            "file_name": file_name,
            "bytes_base64": base64.b64encode(data).decode("ascii"),
            "category": category,
        }
        with httpx.Client(timeout=180.0) as client:
            response = client.post(self._upload_url, headers=self._headers, json=payload)
            if response.status_code >= 400:
                logger.error(
                    "Dropbox file upload failed: %s %s",
                    response.status_code,
                    response.text[:300],
                )
                # Fallback to direct if edge says too large / OOM.
                if response.status_code in {413, 546} or "USE_DIRECT_UPLOAD" in response.text:
                    return self._upload_direct(
                        data=data,
                        company_id=company_id,
                        file_name=file_name,
                        category=category,
                    )
                response.raise_for_status()
            data_json = response.json()
        path = data_json.get("path") or ""
        link = data_json.get("temporary_link") or data_json.get("temporaryLink") or ""
        if not path:
            raise RuntimeError("Dropbox upload mangler path")
        return DropboxUploadResult(path=path, share_url=link)

    def _fetch_dropbox_auth(
        self, *, company_id: str, file_name: str, category: str
    ) -> dict:
        with httpx.Client(timeout=30.0) as client:
            response = client.post(
                self._auth_url,
                headers=self._headers,
                json={
                    "company_id": company_id,
                    "file_name": file_name,
                    "category": category,
                },
            )
            if response.status_code >= 400:
                logger.error(
                    "dropbox_auth failed: %s %s",
                    response.status_code,
                    response.text[:300],
                )
                response.raise_for_status()
            return response.json()

    def _upload_direct(
        self,
        *,
        data: bytes,
        company_id: str,
        file_name: str,
        category: str,
    ) -> DropboxUploadResult:
        auth = self._fetch_dropbox_auth(
            company_id=company_id, file_name=file_name, category=category
        )
        token = auth.get("access_token")
        path = auth.get("suggested_path")
        if not token or not path:
            raise RuntimeError("dropbox_auth mangler token/path")

        headers_base = {"Authorization": f"Bearer {token}"}
        # Ensure parent folder exists (best-effort).
        folder = str(Path(path).parent).replace("\\", "/")
        if not folder.startswith("/"):
            folder = f"/{folder}"
        try:
            with httpx.Client(timeout=30.0) as client:
                client.post(
                    "https://api.dropboxapi.com/2/files/create_folder_v2",
                    headers={**headers_base, "Content-Type": "application/json"},
                    json={"path": folder, "autorename": False},
                )
        except Exception:
            pass

        if len(data) <= _DROPBOX_SIMPLE_MAX:
            import json as _json

            with httpx.Client(timeout=300.0) as client:
                up = client.post(
                    "https://content.dropboxapi.com/2/files/upload",
                    headers={
                        **headers_base,
                        "Content-Type": "application/octet-stream",
                        "Dropbox-API-Arg": _json.dumps(
                            {"path": path, "mode": "add", "autorename": True}
                        ),
                    },
                    content=data,
                )
                if up.status_code >= 400:
                    logger.error("Direct Dropbox upload failed: %s %s", up.status_code, up.text[:300])
                    up.raise_for_status()
                meta = up.json()
        else:
            # Upload session for very large files (chunked).
            meta = self._upload_session(token=token, path=path, data=data)

        final_path = meta.get("path_display") or meta.get("path_lower") or path

        with httpx.Client(timeout=30.0) as client:
            link_res = client.post(
                "https://api.dropboxapi.com/2/files/get_temporary_link",
                headers={**headers_base, "Content-Type": "application/json"},
                json={"path": final_path},
            )
            link = ""
            if link_res.is_success:
                link = (link_res.json() or {}).get("link") or ""

        logger.info("Direct Dropbox upload OK: %s (%d bytes)", final_path, len(data))
        return DropboxUploadResult(path=final_path, share_url=link)

    def _upload_session(self, *, token: str, path: str, data: bytes) -> dict:
        import json as _json

        chunk = 8 * 1024 * 1024
        headers_base = {"Authorization": f"Bearer {token}"}
        with httpx.Client(timeout=300.0) as client:
            start = client.post(
                "https://content.dropboxapi.com/2/files/upload_session/start",
                headers={
                    **headers_base,
                    "Content-Type": "application/octet-stream",
                    "Dropbox-API-Arg": _json.dumps({"close": False}),
                },
                content=data[:chunk],
            )
            start.raise_for_status()
            session_id = start.json()["session_id"]
            offset = min(chunk, len(data))
            while offset < len(data):
                end = min(offset + chunk, len(data))
                piece = data[offset:end]
                close = end >= len(data)
                if close:
                    fin = client.post(
                        "https://content.dropboxapi.com/2/files/upload_session/finish",
                        headers={
                            **headers_base,
                            "Content-Type": "application/octet-stream",
                            "Dropbox-API-Arg": _json.dumps(
                                {
                                    "cursor": {"session_id": session_id, "offset": offset},
                                    "commit": {
                                        "path": path,
                                        "mode": "add",
                                        "autorename": True,
                                    },
                                }
                            ),
                        },
                        content=piece,
                    )
                    fin.raise_for_status()
                    return fin.json()
                app = client.post(
                    "https://content.dropboxapi.com/2/files/upload_session/append_v2",
                    headers={
                        **headers_base,
                        "Content-Type": "application/octet-stream",
                        "Dropbox-API-Arg": _json.dumps(
                            {
                                "cursor": {"session_id": session_id, "offset": offset},
                                "close": False,
                            }
                        ),
                    },
                    content=piece,
                )
                app.raise_for_status()
                offset = end
            # Exact multiple of chunk: finish with empty body
            fin = client.post(
                "https://content.dropboxapi.com/2/files/upload_session/finish",
                headers={
                    **headers_base,
                    "Content-Type": "application/octet-stream",
                    "Dropbox-API-Arg": _json.dumps(
                        {
                            "cursor": {"session_id": session_id, "offset": offset},
                            "commit": {"path": path, "mode": "add", "autorename": True},
                        }
                    ),
                },
                content=b"",
            )
            fin.raise_for_status()
            return fin.json()

    def push_live_jpeg(
        self,
        *,
        image_bytes: bytes,
        camera_db_id: str,
    ) -> DropboxUploadResult:
        """Overwrite latest live frame for worldwide DriftPro preview."""
        payload = {
            "camera_id": camera_db_id,
            "bytes_base64": base64.b64encode(image_bytes).decode("ascii"),
        }
        url = self._upload_url.replace("action=upload", "action=live_push")
        with httpx.Client(timeout=60.0) as client:
            response = client.post(url, headers=self._headers, json=payload)
            if response.status_code >= 400:
                logger.error(
                    "Live push failed: %s %s",
                    response.status_code,
                    response.text[:300],
                )
                response.raise_for_status()
            data = response.json()
        path = data.get("path") or ""
        link = data.get("temporary_link") or data.get("temporaryLink") or ""
        if not path:
            raise RuntimeError("Live push mangler path")
        return DropboxUploadResult(path=path, share_url=link)
