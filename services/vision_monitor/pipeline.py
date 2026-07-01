"""Async orchestration: camera → YOLO entry → Dropbox/Supabase or local dev."""

from __future__ import annotations

import asyncio
import logging
import time
import uuid
from datetime import datetime, timezone

from camera import IpCamera, encode_jpeg
from config import EventType, Settings
from db_client import VisionEventRecord, VisionEventRepository
from detector import PersonEntryDetector
from dropbox_client import DropboxSnapshotStore
from local_server import STATE, start_local_server
from local_store import LocalEvent, LocalEventStore
from supabase_dropbox import SupabaseDropboxUpload
from uniform_detector import UniformViolationDetector

logger = logging.getLogger(__name__)


class VisionMonitorPipeline:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._camera = IpCamera(settings)
        self._is_uniform = settings.event_type == EventType.UNIFORM_VIOLATION
        self._detector = (
            UniformViolationDetector(
                settings.yolo_model,
                confidence_threshold=settings.confidence_threshold,
                violation_cooldown_seconds=settings.entry_cooldown_seconds,
            )
            if self._is_uniform
            else PersonEntryDetector(
                settings.yolo_model,
                confidence_threshold=settings.confidence_threshold,
                entry_cooldown_seconds=settings.entry_cooldown_seconds,
            )
        )
        self._local_store = LocalEventStore(settings.local_captures_dir) if settings.local_dev else None
        if self._local_store is not None:
            STATE.hydrate_events(self._local_store.events)
        self._dropbox = (
            None
            if settings.local_dev or not settings.dropbox_access_token
            else DropboxSnapshotStore(settings.dropbox_access_token, settings.dropbox_root_folder)
        )
        self._company_dropbox = (
            None
            if settings.local_dev or not settings.supabase_service_role_key
            else SupabaseDropboxUpload(settings.supabase_url, settings.supabase_service_role_key)
        )
        self._repo = (
            None
            if settings.local_dev or not settings.supabase_service_role_key
            else VisionEventRepository(settings.supabase_url, settings.supabase_service_role_key)
        )
        self._running = False
        self._http_server = None

    async def run(self) -> None:
        self._running = True

        if self._settings.local_dev:
            self._http_server = start_local_server(
                self._settings.local_server_port,
                captures_dir=self._settings.local_captures_dir,
            )
            logger.info(
                "Dashboard: http://127.0.0.1:%s  (LAN: http://<din-mac-ip>:%s)",
                self._settings.local_server_port,
                self._settings.local_server_port,
            )

        while self._running:
            try:
                await asyncio.to_thread(self._camera.open)
                break
            except Exception as exc:
                STATE.status = f"camera_error: {exc}"
                logger.error("Camera open failed: %s", exc)
                if not self._settings.local_dev:
                    raise
                logger.info("Retrying camera in 5s — set CAMERA_PASSWORD in .env if needed")
                await asyncio.sleep(5)
                self._camera.close()

        STATE.camera_url = self._camera._active_url  # noqa: SLF001
        STATE.camera_mode = self._camera._mode.value  # noqa: SLF001
        STATE.status = "running"

        if self._repo and not await self._repo.health_check():
            logger.warning("Supabase health check failed — continuing")

        logger.info(
            "Vision monitor started | camera=%s mode=%s local_dev=%s dashboard=http://127.0.0.1:%s",
            self._settings.camera_id,
            self._camera._mode.value,  # noqa: SLF001
            self._settings.local_dev,
            self._settings.local_server_port,
        )

        await asyncio.gather(self._capture_loop(), self._detect_loop())

    async def _capture_loop(self) -> None:
        """Hent kamerabilder kontinuerlig — uavhengig av YOLO."""
        while self._running:
            packet = await asyncio.to_thread(self._camera.read)
            if packet is None:
                logger.warning("Lost camera frame — reconnecting in 2s")
                STATE.status = "reconnecting"
                await asyncio.sleep(2)
                await asyncio.to_thread(self._reconnect_camera)
                STATE.status = "running"
                continue

            STATE.set_frame(packet.frame, frame_index=packet.frame_index)

    async def _detect_loop(self) -> None:
        """YOLO / uniform-sjekk på nyeste ramme — blokkerer ikke live-visning."""
        skip_counter = 0
        last_seen_index = -1
        while self._running:
            frame, frame_index = STATE.copy_latest_frame()
            if frame is None:
                await asyncio.sleep(0.1)
                continue
            if frame_index == last_seen_index:
                await asyncio.sleep(0.05)
                continue
            last_seen_index = frame_index

            try:
                if hasattr(self._detector, "analyze_frame"):
                    persons, entries, feed = await asyncio.to_thread(
                        self._detector.analyze_frame, frame  # type: ignore[union-attr]
                    )
                    STATE.set_scan(persons, active=self._settings.local_dev)
                    if feed:
                        STATE.push_feed(feed)
                else:
                    skip_counter += 1
                    if skip_counter % self._settings.frame_skip != 0:
                        await asyncio.sleep(0.2)
                        continue
                    entries = await asyncio.to_thread(self._detector.process_frame, frame)
                    skip_counter = 0
                    for detection in entries:
                        await self._handle_event(frame, detection)
                    await asyncio.sleep(0.2)
                    continue

                skip_counter += 1
                if skip_counter % self._settings.frame_skip != 0:
                    await asyncio.sleep(0.2)
                    continue

                for detection in entries:
                    if persons > 0:
                        await self._handle_event(frame, detection)
            except Exception as exc:
                logger.exception("Detect loop error: %s", exc)
                STATE.push_feed(
                    [
                        {
                            "id": f"err-{int(time.time())}",
                            "status": "violation",
                            "text": "Analysefeil — sjekker på nytt…",
                        }
                    ]
                )

            await asyncio.sleep(0.2)

    async def stop(self) -> None:
        self._running = False
        await asyncio.to_thread(self._camera.close)
        if self._http_server:
            self._http_server.shutdown()
        STATE.status = "stopped"

    def _reconnect_camera(self) -> None:
        self._camera.close()
        self._camera.open()

    async def _handle_event(self, frame, detection) -> None:
        captured_at = datetime.now(timezone.utc)
        crop = await asyncio.to_thread(
            self._detector.crop_person, frame, detection, padding=0.22
        )
        image_bytes = await asyncio.to_thread(
            encode_jpeg,
            crop,
            self._settings.jpeg_quality,
        )

        meta: dict = {
            "track_id": detection.track_id,
            "confidence": round(detection.confidence, 4),
            "bbox": list(detection.bbox),
        }
        if self._is_uniform:
            meta.update(
                {
                    "missing_logo": detection.missing_logo,
                    "missing_shoes": detection.missing_shoes,
                    "logo_score": round(detection.logo_score, 4),
                    "shoes_score": round(detection.shoes_score, 4),
                }
            )

        if self._settings.local_dev and self._local_store:
            filename, path = await asyncio.to_thread(
                self._local_store.save_snapshot,
                image_bytes,
                camera_id=self._settings.camera_id,
                event_type=self._settings.event_type.value,
            )
            image_url = f"http://127.0.0.1:{self._settings.local_server_port}/captures/{filename}"
            event = LocalEvent(
                id=str(uuid.uuid4()),
                timestamp=captured_at.isoformat(),
                camera_id=self._settings.camera_id,
                event_type=self._settings.event_type.value,
                status="open",
                image_url=f"/captures/{filename}",
                image_path=str(path),
                metadata={
                    **meta,
                },
            )
            row = await asyncio.to_thread(self._local_store.append_event, event)
            STATE.add_event(row)
            logger.info("Local event | track=%s file=%s", detection.track_id, filename)
            return

        if self._company_dropbox:
            upload = await asyncio.to_thread(
                self._company_dropbox.upload_jpeg,
                image_bytes=image_bytes,
                company_id=self._settings.company_id,
                camera_id=self._settings.camera_id,
                event_type=self._settings.event_type.value,
                captured_at=captured_at,
            )
        else:
            upload = await asyncio.to_thread(
                self._dropbox.upload_jpeg,  # type: ignore[union-attr]
                image_bytes=image_bytes,
                company_id=self._settings.company_id,
                camera_id=self._settings.camera_id,
                event_type=self._settings.event_type.value,
                captured_at=captured_at,
            )

        record = VisionEventRecord(
            company_id=self._settings.company_id,
            camera_id=self._settings.camera_id,
            event_type=self._settings.event_type.value,
            status="open",
            dropbox_image_url=upload.share_url,
            dropbox_path=upload.path,
            timestamp=captured_at,
            metadata=meta,
        )

        row = await self._repo.insert(record)  # type: ignore[union-attr]
        logger.info(
            "Recorded %s | track=%s url=%s id=%s",
            self._settings.event_type.value,
            detection.track_id,
            upload.share_url,
            row.get("id"),
        )
