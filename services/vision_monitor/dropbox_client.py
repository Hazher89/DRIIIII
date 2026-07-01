"""Dropbox upload + shareable link helper for vision snapshots."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timezone

import dropbox
from dropbox.files import WriteMode
from dropbox.sharing import RequestedVisibility, SharedLinkSettings

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class DropboxUploadResult:
    path: str
    share_url: str
    file_id: str | None


class DropboxSnapshotStore:
    """Uploads JPEG snapshots to Dropbox and returns direct share links."""

    def __init__(self, access_token: str, root_folder: str) -> None:
        self._dbx = dropbox.Dropbox(access_token)
        self._root = root_folder.rstrip("/")

    def upload_jpeg(
        self,
        *,
        image_bytes: bytes,
        company_id: str,
        camera_id: str,
        event_type: str,
        captured_at: datetime | None = None,
    ) -> DropboxUploadResult:
        """Upload image and create (or reuse) a shareable link."""
        ts = captured_at or datetime.now(timezone.utc)
        stamp = ts.strftime("%Y%m%dT%H%M%S_%f")
        safe_cam = _sanitize_path_segment(camera_id)
        safe_event = _sanitize_path_segment(event_type)
        filename = f"{stamp}_{safe_cam}_{safe_event}.jpg"

        dropbox_path = (
            f"{self._root}/company_{company_id}/{safe_cam}/{ts:%Y/%m/%d}/{filename}"
        )

        logger.info("Uploading snapshot to Dropbox: %s", dropbox_path)
        metadata = self._dbx.files_upload(
            image_bytes,
            dropbox_path,
            mode=WriteMode.add,
            mute=True,
        )

        share_url = self._ensure_shared_link(dropbox_path)
        return DropboxUploadResult(
            path=dropbox_path,
            share_url=share_url,
            file_id=metadata.id,
        )

    def _ensure_shared_link(self, path: str) -> str:
        """Return a direct-view URL suitable for <img src=...> in the web app."""
        try:
            links = self._dbx.sharing_list_shared_links(path=path, direct_only=True).links
            if links:
                return _to_direct_link(links[0].url)

            created = self._dbx.sharing_create_shared_link_with_settings(
                path,
                settings=SharedLinkSettings(requested_visibility=RequestedVisibility.public),
            )
            return _to_direct_link(created.url)
        except dropbox.exceptions.ApiError as exc:
            # Link may already exist under another settings shape.
            if exc.error.is_shared_link_already_exists():
                existing = self._dbx.sharing_list_shared_links(path=path).links[0]
                return _to_direct_link(existing.url)
            raise


def _to_direct_link(dropbox_url: str) -> str:
    """Convert www.dropbox.com/s/...?dl=0 to dl.dropboxusercontent.com for embedding."""
    return (
        dropbox_url.replace("www.dropbox.com", "dl.dropboxusercontent.com")
        .replace("?dl=0", "")
        .replace("?dl=1", "")
    )


def _sanitize_path_segment(value: str) -> str:
    return "".join(c if c.isalnum() or c in "-_" else "_" for c in value.strip())[:64]
