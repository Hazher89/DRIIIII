"""Async orchestration: camera → detect → Dropbox/Supabase or local clips."""

from __future__ import annotations

import asyncio
import logging
import os
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

from camera import IpCamera, encode_jpeg
from config import EventType, Settings
from db_client import VisionEventRecord, VisionEventRepository
from detector import PersonEntryDetector
from dropbox_client import DropboxSnapshotStore
from frame_ring_buffer import FrameRingBuffer
from local_server import STATE, start_local_server
from local_store import LocalEvent, LocalEventStore
from sorting_detector import CompactorZone, SortingDetector, SortingHit
from supabase_dropbox import SupabaseDropboxUpload
from uniform_detector import UniformViolationDetector
from video_clip import write_clip_mp4

logger = logging.getLogger(__name__)


class VisionMonitorPipeline:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._camera = IpCamera(settings)
        self._is_uniform = settings.event_type == EventType.UNIFORM_VIOLATION
        self._is_sorting = settings.event_type == EventType.SORTING_CLIP

        if self._is_sorting:
            z1 = settings.zone1_rect
            z2 = settings.zone2_rect
            self._detector = SortingDetector(
                settings.sorting_model,
                confidence_threshold=settings.confidence_threshold,
                cooldown_seconds=settings.entry_cooldown_seconds,
                zones=[
                    CompactorZone(settings.zone1_name, z1[0], z1[2], z1[1], z1[3]),
                    CompactorZone(settings.zone2_name, z2[0], z2[2], z2[1], z2[3]),
                ],
            )
        elif self._is_uniform:
            self._detector = UniformViolationDetector(
                settings.yolo_model,
                confidence_threshold=settings.confidence_threshold,
                violation_cooldown_seconds=settings.entry_cooldown_seconds,
            )
        else:
            self._detector = PersonEntryDetector(
                settings.yolo_model,
                confidence_threshold=settings.confidence_threshold,
                entry_cooldown_seconds=settings.entry_cooldown_seconds,
            )

        self._ring = FrameRingBuffer(
            seconds=settings.clip_seconds_before + 5.0,
            target_fps=settings.clip_fps,
        )
        self._pending_clips: list[dict] = []
        self._local_store = LocalEventStore(settings.local_captures_dir) if settings.local_dev else None
        if self._local_store is not None:
            STATE.hydrate_events(self._local_store.events)
        self._dropbox = (
            None
            if not settings.dropbox_access_token
            else DropboxSnapshotStore(settings.dropbox_access_token, settings.dropbox_root_folder)
        )
        self._company_dropbox = (
            None
            if not settings.supabase_service_role_key
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

        if self._settings.local_dev or os.environ.get("LOCAL_SERVER", "true").lower() in {
            "1",
            "true",
            "yes",
        }:
            self._http_server = start_local_server(
                self._settings.local_server_port,
                captures_dir=self._settings.local_captures_dir,
            )
            logger.info(
                "Dashboard: http://127.0.0.1:%s",
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
                logger.info(
                    "Retrying camera in 5s — sett CAMERA_HOST / CAMERA_PASSWORD i .env "
                    "(lokal IP på jobb-nett, ikke mydlink-sky)"
                )
                await asyncio.sleep(5)
                self._camera.close()

        STATE.camera_url = self._camera._active_url  # noqa: SLF001
        STATE.camera_mode = self._camera._mode.value  # noqa: SLF001
        STATE.status = "running"

        if self._repo and not await self._repo.health_check():
            logger.warning("Supabase health check failed — continuing")

        logger.info(
            "Vision monitor started | camera=%s mode=%s event=%s local_dev=%s",
            self._settings.camera_id,
            self._camera._mode.value,  # noqa: SLF001
            self._settings.event_type.value,
            self._settings.local_dev,
        )

        await asyncio.gather(
            self._capture_loop(),
            self._detect_loop(),
            self._clip_finalize_loop(),
            self._live_push_loop(),
        )

    async def _capture_loop(self) -> None:
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
            if self._is_sorting:
                self._ring.push(packet.frame, quality=70)
                now = time.monotonic()
                min_gap = 1.0 / max(0.5, self._settings.clip_fps)
                for pending in self._pending_clips:
                    if now > pending["until"]:
                        continue
                    last = pending.get("last_post", 0.0)
                    if now - last < min_gap:
                        continue
                    pending["last_post"] = now
                    pending["post"].append(packet.frame.copy())

    async def _detect_loop(self) -> None:
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
                if self._is_sorting:
                    skip_counter += 1
                    if skip_counter % self._settings.frame_skip != 0:
                        await asyncio.sleep(0.15)
                        continue
                    objects, hits, feed = await asyncio.to_thread(
                        self._detector.analyze_frame, frame  # type: ignore[union-attr]
                    )
                    STATE.set_scan(objects, active=self._settings.local_dev)
                    if feed:
                        STATE.push_feed(feed)
                    for hit in hits:
                        await self._queue_sorting_clip(hit)
                    await asyncio.sleep(0.15)
                    continue

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

    async def _clip_finalize_loop(self) -> None:
        """When post-window elapses, write MP4 from before+after frames."""
        while self._running:
            now = time.monotonic()
            ready = [p for p in self._pending_clips if now >= p["until"]]
            self._pending_clips = [p for p in self._pending_clips if now < p["until"]]
            for pending in ready:
                try:
                    await self._finalize_sorting_clip(pending)
                except Exception as exc:
                    logger.exception("Clip finalize failed: %s", exc)
            await asyncio.sleep(0.5)

    async def _queue_sorting_clip(self, hit: SortingHit) -> None:
        pre = self._ring.snapshot()
        captured_at = datetime.now(timezone.utc)
        pending = {
            "id": str(uuid.uuid4()),
            "hit": hit,
            "pre": pre,
            "post": [],
            "last_post": 0.0,
            "until": time.monotonic() + self._settings.clip_seconds_after,
            "captured_at": captured_at,
        }
        self._pending_clips.append(pending)
        STATE.push_feed(
            [
                {
                    "id": f"rec-{pending['id'][:8]}",
                    "status": "violation",
                    "text": (
                        f"Tar opp klipp ({self._settings.clip_seconds_before:.0f}s før + "
                        f"{self._settings.clip_seconds_after:.0f}s etter) — {hit.zone}"
                    ),
                }
            ]
        )
        logger.info(
            "Sorting trigger | zone=%s reason=%s label=%s conf=%.2f — recording post window",
            hit.zone,
            hit.reason,
            hit.label,
            hit.confidence,
        )

        # Immediate still as preview
        snap = await asyncio.to_thread(
            encode_jpeg, hit.annotated_frame, self._settings.jpeg_quality
        )
        meta = {
            "zone": hit.zone,
            "reason": hit.reason,
            "label": hit.label,
            "confidence": round(hit.confidence, 4),
            "bbox": list(hit.bbox),
            "clip_status": "recording",
        }
        if self._settings.local_dev and self._local_store:
            filename, path = await asyncio.to_thread(
                self._local_store.save_snapshot,
                snap,
                camera_id=self._settings.camera_id,
                event_type=self._settings.event_type.value,
            )
            event = LocalEvent(
                id=pending["id"],
                timestamp=captured_at.isoformat(),
                camera_id=self._settings.camera_id,
                event_type=self._settings.event_type.value,
                status="recording",
                image_url=f"/captures/{filename}",
                image_path=str(path),
                metadata=meta,
            )
            row = await asyncio.to_thread(self._local_store.append_event, event)
            STATE.add_event(row)

    async def _finalize_sorting_clip(self, pending: dict) -> None:
        hit: SortingHit = pending["hit"]
        captured_at: datetime = pending["captured_at"]
        pre = pending["pre"]
        # Encode post frames into buffer format
        from frame_ring_buffer import BufferedFrame

        post_bufs: list[BufferedFrame] = []
        for frame in pending["post"]:
            import cv2

            ok, encoded = cv2.imencode(
                ".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 70]
            )
            if not ok:
                continue
            h, w = frame.shape[:2]
            post_bufs.append(
                BufferedFrame(t=time.monotonic(), jpeg=encoded.tobytes(), width=w, height=h)
            )

        all_frames = list(pre) + post_bufs
        if len(all_frames) < 4:
            logger.warning("Too few frames for clip (%d) — skipping video", len(all_frames))
            return

        stamp = captured_at.strftime("%Y%m%dT%H%M%S")
        base = Path(self._settings.local_captures_dir) / (
            f"{stamp}_{self._settings.camera_id}_{hit.zone}_{hit.reason}"
        )
        video_path = await asyncio.to_thread(
            write_clip_mp4,
            all_frames,
            base,
            fps=self._settings.clip_fps,
        )

        meta = {
            "zone": hit.zone,
            "reason": hit.reason,
            "label": hit.label,
            "confidence": round(hit.confidence, 4),
            "bbox": list(hit.bbox),
            "clip_status": "ready",
            "clip_seconds_before": self._settings.clip_seconds_before,
            "clip_seconds_after": self._settings.clip_seconds_after,
            "frame_count": len(all_frames),
            "video_path": str(video_path),
        }

        if self._settings.local_dev and self._local_store:
            # Update event metadata if present
            await asyncio.to_thread(
                self._local_store.update_event_metadata, pending["id"], meta
            )
            STATE.push_feed(
                [
                    {
                        "id": f"done-{pending['id'][:8]}",
                        "status": "ok",
                        "text": f"Klipp lagret: {video_path.name}",
                    }
                ]
            )
            logger.info("Local sorting clip ready: %s", video_path)
            return

        # Production: upload video bytes via Dropbox if configured
        video_bytes = await asyncio.to_thread(video_path.read_bytes)
        snap = await asyncio.to_thread(
            encode_jpeg, hit.annotated_frame, self._settings.jpeg_quality
        )

        if self._company_dropbox:
            upload = await asyncio.to_thread(
                self._company_dropbox.upload_jpeg,
                image_bytes=snap,
                company_id=self._settings.company_id,
                camera_id=self._settings.camera_id,
                event_type=self._settings.event_type.value,
                captured_at=captured_at,
            )
        elif self._dropbox:
            upload = await asyncio.to_thread(
                self._dropbox.upload_bytes,
                data=video_bytes,
                company_id=self._settings.company_id,
                camera_id=self._settings.camera_id,
                event_type=self._settings.event_type.value,
                captured_at=captured_at,
                extension="mp4",
            )
        else:
            logger.warning("No Dropbox configured — clip kept at %s", video_path)
            return

        if self._repo:
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
            await self._repo.insert(record)
        logger.info("Sorting clip uploaded | zone=%s path=%s", hit.zone, upload.path)

    async def _live_push_loop(self) -> None:
        """Push nearly-live JPEG to Dropbox so DriftPro can show camera worldwide."""
        cam_id = self._settings.vision_camera_db_id
        interval = max(1.0, self._settings.live_push_interval_seconds)
        if not cam_id or not self._company_dropbox:
            logger.info(
                "Live push disabled (VISION_CAMERA_ID / SUPABASE_SERVICE_ROLE_KEY mangler)"
            )
            while self._running:
                await asyncio.sleep(30)
            return

        logger.info(
            "Live push every %.1fs → camera %s",
            interval,
            cam_id,
        )
        while self._running:
            await asyncio.sleep(interval)
            jpeg, _, _ = STATE.snapshot()
            if not jpeg:
                continue
            try:
                await asyncio.to_thread(
                    self._company_dropbox.push_live_jpeg,
                    image_bytes=jpeg,
                    camera_db_id=cam_id,
                )
            except Exception as exc:
                logger.warning("Live push failed: %s", exc)

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
            event = LocalEvent(
                id=str(uuid.uuid4()),
                timestamp=captured_at.isoformat(),
                camera_id=self._settings.camera_id,
                event_type=self._settings.event_type.value,
                status="open",
                image_url=f"/captures/{filename}",
                image_path=str(path),
                metadata=meta,
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
