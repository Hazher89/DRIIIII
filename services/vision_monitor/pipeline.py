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
            # Person presence → clip window (1 min før ankomst, 2 min etter avgang).
            self._person_watcher: PersonEntryDetector | None = PersonEntryDetector(
                settings.person_model,
                confidence_threshold=0.35,
                entry_cooldown_seconds=1.0,
            )
        elif self._is_uniform:
            self._detector = UniformViolationDetector(
                settings.yolo_model,
                confidence_threshold=settings.confidence_threshold,
                violation_cooldown_seconds=settings.entry_cooldown_seconds,
            )
            self._person_watcher = None
        else:
            self._detector = PersonEntryDetector(
                settings.yolo_model,
                confidence_threshold=settings.confidence_threshold,
                entry_cooldown_seconds=settings.entry_cooldown_seconds,
            )
            self._person_watcher = None

        self._ring = FrameRingBuffer(
            seconds=settings.clip_seconds_before + 5.0,
            target_fps=settings.clip_fps,
        )
        self._pending_clips: list[dict] = []
        # Person-episode for sorting: lagre ALLE besøk for menneske-merking (Riktig/Feil).
        self._sorting_episode: dict | None = None
        # Kort hale etter OK-besøk (full 2 min kun ved auto-detektert feil).
        self._ok_visit_post_seconds = float(
            os.environ.get("CLIP_SECONDS_AFTER_OK", "30")
        )
        self._person_absent_since: float | None = None
        self._max_episode_seconds = float(
            os.environ.get("CLIP_MAX_EPISODE_SECONDS", "600")
        )
        self._person_leave_grace = 2.5  # avoid flicker before starting post window
        self._learn_visit: dict | None = None
        self._learn_person_absent_since: float | None = None
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
        # Always create repo when service role is set (events + learn mode).
        self._repo = (
            None
            if not settings.supabase_service_role_key
            else VisionEventRepository(settings.supabase_url, settings.supabase_service_role_key)
        )
        self._running = False
        self._http_server = None

        # Læremodus: kontinuerlig chunk-opptak styrt fra DriftPro.
        self._learn_active = False
        self._learn_session_id: str | None = None
        self._learn_frames: list = []
        self._learn_chunk_started = 0.0
        self._learn_paths: list[str] = []
        self._learn_chunk_seconds = 300.0  # 5 min chunks
        self._learn_started_wall: datetime | None = None
        self._learn_last_push = 0.0
        self._learn_finalizing = False
        # Event-company = kamera (inkl. MAVI 00000000). Dropbox-company = OAuth-kobling.
        self._event_company_id = settings.company_id
        self._dropbox_company_id = settings.company_id
        self._upload_company_id = settings.company_id  # alias → event (bakoverkompatibel)

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

        # MAVI bruker company_id 00000000 i DB — det er IKKE en placeholder.
        # Dropbox er koblet på DriftPro Demo (d190e74c). Skill de to:
        # - vision_events → COMPANY_ID fra .env (så DriftPro RLS/UI finner dem)
        # - filer → Dropbox-company (så opplasting fungerer)
        # Ikke overstyr event-company fra kamera — UI-lagring under Demo har
        # tidligere flyttet kamera.company_id og skjult alle klipp for MAVI.
        if self._repo:
            try:
                dropbox_co = await self._repo.fetch_dropbox_company_id()
                if dropbox_co:
                    self._dropbox_company_id = dropbox_co
                    logger.info("Dropbox company_id: %s", dropbox_co)
            except Exception as exc:
                logger.warning("Dropbox company lookup failed: %s", exc)
        if not self._event_company_id:
            cam_id = self._settings.vision_camera_db_id
            if self._repo and cam_id:
                try:
                    resolved = await self._repo.fetch_camera_company_id(cam_id)
                    if resolved:
                        self._event_company_id = resolved
                        logger.info("Event company_id from camera (fallback): %s", resolved)
                except Exception as exc:
                    logger.warning("Could not resolve camera company_id: %s", exc)
        if not self._dropbox_company_id:
            self._dropbox_company_id = self._event_company_id
        self._upload_company_id = self._event_company_id
        logger.info(
            "Event company_id from .env COMPANY_ID: %s",
            self._event_company_id,
        )

        logger.info(
            "Vision monitor started | camera=%s mode=%s event=%s local_dev=%s "
            "event_company=%s dropbox_company=%s",
            self._settings.camera_id,
            self._camera._mode.value,  # noqa: SLF001
            self._settings.event_type.value,
            self._settings.local_dev,
            self._event_company_id,
            self._dropbox_company_id,
        )

        await asyncio.gather(
            self._capture_loop(),
            self._detect_loop(),
            self._clip_finalize_loop(),
            self._live_push_loop(),
            self._learn_poll_loop(),
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
                self._maybe_buffer_learn_frame(packet.frame)
                now = time.monotonic()
                min_gap = 1.0 / max(0.5, self._settings.clip_fps)
                # Legacy pending clips (should be empty) + active person episode.
                for pending in self._pending_clips:
                    if now > pending["until"]:
                        continue
                    last = pending.get("last_post", 0.0)
                    if now - last < min_gap:
                        continue
                    pending["last_post"] = now
                    pending["post"].append(packet.frame.copy())
                ep = self._sorting_episode
                if ep is not None and not ep.get("closed"):
                    last = ep.get("last_post", 0.0)
                    if now - last >= min_gap:
                        ep["last_post"] = now
                        ep["post"].append(packet.frame.copy())
                lv = getattr(self, "_learn_visit", None)
                if lv is not None and not lv.get("closed"):
                    last = lv.get("last_post", 0.0)
                    if now - last >= min_gap:
                        lv["last_post"] = now
                        lv["post"].append(packet.frame.copy())

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
                    # Under læremodus: ta opp hvert personbesøk (riktig og feil).
                    if self._learn_active:
                        skip_counter += 1
                        if skip_counter % self._settings.frame_skip != 0:
                            await asyncio.sleep(0.2)
                            continue
                        persons = 0
                        if self._person_watcher is not None:
                            persons = await asyncio.to_thread(
                                self._person_watcher.count_visible, frame
                            )
                        objects, hits, feed = await asyncio.to_thread(
                            self._detector.analyze_frame, frame  # type: ignore[union-attr]
                        )
                        STATE.set_scan(max(objects, persons), active=True)
                        if feed:
                            STATE.push_feed(feed)
                        await self._update_learn_visit(persons=persons, hits=hits)
                        await asyncio.sleep(0.2)
                        continue
                    skip_counter += 1
                    if skip_counter % self._settings.frame_skip != 0:
                        await asyncio.sleep(0.15)
                        continue
                    objects, hits, feed = await asyncio.to_thread(
                        self._detector.analyze_frame, frame  # type: ignore[union-attr]
                    )
                    persons = 0
                    if self._person_watcher is not None:
                        persons = await asyncio.to_thread(
                            self._person_watcher.count_visible, frame
                        )
                    STATE.set_scan(max(objects, persons), active=self._settings.local_dev)
                    if feed:
                        STATE.push_feed(feed)
                    await self._update_sorting_episode(
                        persons=persons, hits=hits, frame=frame
                    )
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
        """Finalize person-episodes (and any legacy pending clips)."""
        while self._running:
            now = time.monotonic()
            ready = [p for p in self._pending_clips if now >= p["until"]]
            self._pending_clips = [p for p in self._pending_clips if now < p["until"]]
            for pending in ready:
                try:
                    await self._finalize_sorting_clip(pending)
                except Exception as exc:
                    logger.exception("Clip finalize failed: %s", exc)

            ep = self._sorting_episode
            if ep is not None and not ep.get("closed"):
                # Hard cap: person standing forever.
                if now - ep["started"] >= self._max_episode_seconds:
                    ep["until"] = now
                    ep["person_present"] = False
                    logger.info(
                        "Sorting episode hit max duration (%.0fs) — finalizing",
                        self._max_episode_seconds,
                    )
                if ep.get("until") is not None and now >= ep["until"] and not ep.get("person_present"):
                    ep["closed"] = True
                    try:
                        await self._finalize_sorting_episode(ep)
                    except Exception as exc:
                        logger.exception("Episode finalize failed: %s", exc)
                    finally:
                        self._sorting_episode = None

            await asyncio.sleep(0.5)

    async def _update_sorting_episode(
        self,
        *,
        persons: int,
        hits: list[SortingHit],
        frame,
    ) -> None:
        """Track person visit; always save clip for human Riktig/Feil review."""
        now = time.monotonic()
        ep = self._sorting_episode

        if persons > 0:
            self._person_absent_since = None
            if ep is None:
                pre = self._ring.snapshot()
                self._sorting_episode = {
                    "id": str(uuid.uuid4()),
                    "pre": pre,
                    "post": [],
                    "last_post": 0.0,
                    "hit": None,
                    "started": now,
                    "person_present": True,
                    "until": None,
                    "captured_at": datetime.now(timezone.utc),
                    "closed": False,
                    "last_frame": frame.copy() if frame is not None else None,
                }
                ep = self._sorting_episode
                logger.info(
                    "Person arrived — buffering visit (pre=%.0fs). "
                    "Alle besøk lagres for merking i DriftPro.",
                    self._settings.clip_seconds_before,
                )
                STATE.push_feed(
                    [
                        {
                            "id": f"arr-{ep['id'][:8]}",
                            "status": "ok",
                            "text": "Person i bilde — tar opp besøk (merke Riktig/Feil i DriftPro)",
                        }
                    ]
                )
            else:
                ep["person_present"] = True
                if frame is not None:
                    ep["last_frame"] = frame.copy()
                if ep.get("until") is not None:
                    ep["until"] = None
                    logger.info("Person returned during post-window — extending episode")
        else:
            if ep is not None and ep.get("person_present"):
                if self._person_absent_since is None:
                    self._person_absent_since = now
                elif now - self._person_absent_since >= self._person_leave_grace:
                    ep["person_present"] = False
                    self._person_absent_since = None
                    if ep.get("hit"):
                        post_s = self._settings.clip_seconds_after
                        ep["until"] = now + post_s
                        logger.info(
                            "Person left after suspected wrong — recording %.0fs more then save",
                            post_s,
                        )
                        STATE.push_feed(
                            [
                                {
                                    "id": f"leave-{ep['id'][:8]}",
                                    "status": "violation",
                                    "text": (
                                        f"Mulig feilkasting — tar {post_s:.0f}s "
                                        f"etter avgang, deretter lagring til vurdering"
                                    ),
                                }
                            ]
                        )
                    else:
                        post_s = self._ok_visit_post_seconds
                        ep["until"] = now + post_s
                        logger.info(
                            "Person left — saving visit for review (post=%.0fs)",
                            post_s,
                        )
                        STATE.push_feed(
                            [
                                {
                                    "id": f"okleave-{ep['id'][:8]}",
                                    "status": "ok",
                                    "text": (
                                        f"Besøk ferdig — lagrer klipp ({post_s:.0f}s hale) "
                                        f"til Riktig/Feil i DriftPro"
                                    ),
                                }
                            ]
                        )

        if hits and ep is not None:
            if frame is not None:
                ep["last_frame"] = frame.copy()
            if ep.get("hit") is None:
                hit = hits[0]
                ep["hit"] = hit
                logger.info(
                    "Suspected wrong during visit | zone=%s reason=%s label=%s conf=%.2f — "
                    "will save for human review",
                    hit.zone,
                    hit.reason,
                    hit.label,
                    hit.confidence,
                )
                STATE.push_feed(
                    [
                        {
                            "id": f"bad-{ep['id'][:8]}",
                            "status": "violation",
                            "text": (
                                f"AUTO-forslag FEIL: {hit.zone} — venter til personen går, "
                                f"deretter lagring (du bekrefter i DriftPro)"
                            ),
                        }
                    ]
                )
        elif hits and ep is None:
            hit = hits[0]
            logger.info(
                "Sorting signal without person (zone=%s reason=%s) — not saving",
                hit.zone,
                hit.reason,
            )
            STATE.push_feed(
                [
                    {
                        "id": f"noperson-{int(now)}",
                        "status": "ok",
                        "text": "Ser mulig feil uten person — venter på person før lagring",
                    }
                ]
            )

    async def _finalize_sorting_episode(self, ep: dict) -> None:
        auto_suspected = ep.get("hit") is not None
        hit = ep.get("hit")
        if hit is None:
            frame = ep.get("last_frame")
            if frame is None and ep.get("post"):
                frame = ep["post"][-1]
            if frame is None:
                logger.info(
                    "Episode discarded — no frames for visit (pre=%d)",
                    len(ep.get("pre") or []),
                )
                return
            h, w = frame.shape[:2]
            hit = SortingHit(
                track_id=0,
                confidence=0.0,
                bbox=(0, 0, w, h),
                label="person_visit",
                reason="person_visit",
                zone="visit",
                annotated_frame=frame.copy(),
            )
        pending = {
            "id": ep["id"],
            "hit": hit,
            "pre": ep["pre"],
            "post": ep["post"],
            "captured_at": ep["captured_at"],
            "needs_review": True,
            "auto_suspected_wrong": auto_suspected,
        }
        await self._finalize_sorting_clip(pending)

    async def _queue_sorting_clip(self, hit: SortingHit) -> None:
        """Deprecated fixed-window queue — kept unused; episodes replace this."""
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
            "needs_review": bool(pending.get("needs_review", True)),
            "auto_suspected_wrong": bool(pending.get("auto_suspected_wrong", False)),
            "human_label": None,
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
                        "text": f"Klipp lagret lokalt: {video_path.name}",
                    }
                ]
            )
            logger.info(
                "LOCAL_DEV=true — clip kept local only (no Dropbox): %s. "
                "Sett LOCAL_DEV=false + ENABLE_DROPBOX.ps1 for DriftPro.",
                video_path,
            )
            return

        # Production: always upload VIDEO clip (+ JPEG preview) — never image-only.
        if not self._company_dropbox and not self._dropbox:
            logger.error(
                "No Dropbox configured — MP4 kept at %s. "
                "Sett SUPABASE_SERVICE_ROLE_KEY eller DROPBOX_ACCESS_TOKEN.",
                video_path,
            )
            STATE.push_feed(
                [
                    {
                        "id": f"uperr-{pending['id'][:8]}",
                        "status": "violation",
                        "text": "Video lagret lokalt — Dropbox ikke konfigurert",
                    }
                ]
            )
            return

        video_bytes = await asyncio.to_thread(video_path.read_bytes)
        snap = await asyncio.to_thread(
            encode_jpeg, hit.annotated_frame, self._settings.jpeg_quality
        )
        stamp_name = captured_at.strftime("%Y%m%d_%H%M%S")

        video_upload = None
        thumb_upload = None
        try:
            if self._company_dropbox:
                video_upload = await asyncio.to_thread(
                    self._company_dropbox.upload_file,
                    data=video_bytes,
                    company_id=self._dropbox_company_id,
                    file_name=(
                        f"sorting_{self._settings.camera_id}_{hit.zone}_"
                        f"{hit.reason}_{stamp_name}.mp4"
                    ),
                    category="vision_sorting_clip",
                )
                try:
                    thumb_upload = await asyncio.to_thread(
                        self._company_dropbox.upload_jpeg,
                        image_bytes=snap,
                        company_id=self._dropbox_company_id,
                        camera_id=self._settings.camera_id,
                        event_type=self._settings.event_type.value,
                        captured_at=captured_at,
                    )
                except Exception as exc:
                    logger.warning("Thumbnail upload failed (video OK): %s", exc)
            else:
                video_upload = await asyncio.to_thread(
                    self._dropbox.upload_bytes,  # type: ignore[union-attr]
                    data=video_bytes,
                    company_id=self._dropbox_company_id,
                    camera_id=self._settings.camera_id,
                    event_type=self._settings.event_type.value,
                    captured_at=captured_at,
                    extension="mp4",
                )
        except Exception as exc:
            logger.exception(
                "MP4 upload FAILED — local file kept at %s: %s",
                video_path,
                exc,
            )
            STATE.push_feed(
                [
                    {
                        "id": f"upfail-{pending['id'][:8]}",
                        "status": "violation",
                        "text": f"Video-opplasting feilet — fil: {video_path.name}",
                    }
                ]
            )
            return

        if video_upload is None:
            logger.error("MP4 upload returned empty — kept at %s", video_path)
            return

        meta["dropbox_video_url"] = video_upload.share_url
        meta["dropbox_video_path"] = video_upload.path
        if thumb_upload:
            meta["dropbox_thumb_url"] = thumb_upload.share_url

        if self._repo:
            record = VisionEventRecord(
                company_id=self._event_company_id,
                camera_id=self._settings.camera_id,
                event_type=self._settings.event_type.value,
                status="open",
                dropbox_image_url=(
                    thumb_upload.share_url if thumb_upload else video_upload.share_url
                ),
                dropbox_path=video_upload.path,
                timestamp=captured_at,
                metadata=meta,
            )
            try:
                await self._repo.insert(record)
            except Exception as exc:
                logger.exception(
                    "vision_events insert FAILED after video upload %s: %s",
                    video_upload.path,
                    exc,
                )
                return
        else:
            logger.error(
                "Video uploaded to Dropbox but no Supabase repo "
                "(LOCAL_DEV or missing SERVICE_ROLE) — path=%s",
                video_upload.path,
            )

        STATE.push_feed(
            [
                {
                    "id": f"done-{pending['id'][:8]}",
                    "status": "ok",
                    "text": f"Video lastet opp ({self._settings.clip_seconds_before:.0f}+"
                    f"{self._settings.clip_seconds_after:.0f}s)",
                }
            ]
        )
        logger.info(
            "Sorting VIDEO uploaded | zone=%s reason=%s path=%s",
            hit.zone,
            hit.reason,
            video_upload.path,
        )

    async def _update_learn_visit(
        self,
        *,
        persons: int,
        hits: list[SortingHit],
    ) -> None:
        """Under opplæring: hvert personbesøk → egen video (riktig og feil)."""
        now = time.monotonic()
        lv = self._learn_visit

        if persons > 0:
            self._learn_person_absent_since = None
            if lv is None:
                self._learn_visit = {
                    "pre": self._ring.snapshot(),
                    "post": [],
                    "last_post": 0.0,
                    "started": now,
                    "person_present": True,
                    "until": None,
                    "closed": False,
                    "hit": hits[0] if hits else None,
                }
                logger.info("Learn visit started (person arrived)")
                STATE.push_feed(
                    [
                        {
                            "id": f"learn-arr-{int(now)}",
                            "status": "scan",
                            "text": "Opplæring: person i bilde — tar opp besøket",
                        }
                    ]
                )
            else:
                lv["person_present"] = True
                if lv.get("until") is not None:
                    lv["until"] = None
                if hits and lv.get("hit") is None:
                    lv["hit"] = hits[0]
        else:
            if lv is not None and lv.get("person_present"):
                if self._learn_person_absent_since is None:
                    self._learn_person_absent_since = now
                elif now - self._learn_person_absent_since >= self._person_leave_grace:
                    lv["person_present"] = False
                    # Kort hale etter avgang i opplæring (30s).
                    lv["until"] = now + 30.0
                    self._learn_person_absent_since = None
                    logger.info("Learn visit: person left — 30s then save clip")

        # Hard cap
        if lv is not None and now - lv["started"] >= self._max_episode_seconds:
            lv["until"] = now
            lv["person_present"] = False

    async def _finalize_learn_visit(self, lv: dict) -> None:
        """Always save learn visit (correct or wrong) as a training clip."""
        from frame_ring_buffer import BufferedFrame
        import cv2

        post_bufs: list[BufferedFrame] = []
        for frame in lv.get("post") or []:
            ok, encoded = cv2.imencode(
                ".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 70]
            )
            if not ok:
                continue
            h, w = frame.shape[:2]
            post_bufs.append(
                BufferedFrame(t=time.monotonic(), jpeg=encoded.tobytes(), width=w, height=h)
            )
        all_frames = list(lv.get("pre") or []) + post_bufs
        if len(all_frames) < 4:
            logger.warning("Learn visit too short (%d) — skip", len(all_frames))
            return

        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
        sid = (self._learn_session_id or "nosession")[:8]
        base = Path(self._settings.local_captures_dir) / (
            f"learn_visit_{sid}_{stamp}_{len(self._learn_paths)}"
        )
        video_path = await asyncio.to_thread(
            write_clip_mp4,
            all_frames,
            base,
            fps=self._settings.clip_fps,
        )

        if self._settings.local_dev and not self._company_dropbox:
            logger.warning("Learn visit local only (ikke lagt i session): %s", video_path)
            return

        if not self._company_dropbox:
            logger.error("Learn visit: no Dropbox — kept %s (ikke i session)", video_path)
            return

        video_bytes = await asyncio.to_thread(video_path.read_bytes)
        try:
            upload = await asyncio.to_thread(
                self._company_dropbox.upload_file,
                data=video_bytes,
                company_id=self._dropbox_company_id,
                file_name=(
                    f"learn_{self._settings.camera_id}_{sid}_"
                    f"{stamp}_visit{len(self._learn_paths)}.mp4"
                ),
                category="vision_learn_clip",
            )
            if not upload.path or not str(upload.path).startswith("/"):
                raise RuntimeError(f"Ugyldig Dropbox-path: {upload.path!r}")
            self._learn_paths.append(upload.path)
            logger.info("Learn visit uploaded: %s", upload.path)
            if self._repo and self._learn_session_id:
                await self._repo.patch_learn_session(
                    self._learn_session_id,
                    dropbox_paths=list(self._learn_paths),
                    chunk_count=len(self._learn_paths),
                    dropbox_video_path=upload.path,
                    dropbox_video_url=upload.share_url or None,
                )
            STATE.push_feed(
                [
                    {
                        "id": f"learn-clip-{len(self._learn_paths)}",
                        "status": "ok",
                        "text": f"Opplæringsvideo {len(self._learn_paths)} lagret",
                    }
                ]
            )
        except Exception as exc:
            logger.exception("Learn visit upload failed: %s", exc)
            # Ikke legg lokale stier i dropbox_paths — da feiler DriftPro-avspilling.

    def _maybe_buffer_learn_frame(self, frame) -> None:
        # Besøksbasert opptak håndteres via _learn_visit + capture_loop.
        return

    async def _learn_poll_loop(self) -> None:
        """Poll DriftPro learn_mode; finalize visit clips; apply feedback."""
        cam_id = self._settings.vision_camera_db_id
        if not cam_id or not self._repo:
            logger.info("Learn mode disabled (VISION_CAMERA_ID / SERVICE_ROLE mangler)")
            while self._running:
                await asyncio.sleep(30)
            return

        logger.info("Learn mode poll every 5s → camera %s", cam_id)
        while self._running:
            try:
                state = await self._repo.fetch_learn_state(cam_id)
                if state is None:
                    await asyncio.sleep(5)
                    continue

                if state.learn_mode and not self._learn_active:
                    await self._start_learn_session(state.learn_session_id)
                elif not state.learn_mode and self._learn_active:
                    await self._stop_learn_session()
                elif (
                    state.learn_mode
                    and self._learn_active
                    and state.learn_session_id
                    and state.learn_session_id != self._learn_session_id
                ):
                    await self._stop_learn_session()
                    await self._start_learn_session(state.learn_session_id)

                # Finalize finished learn visits.
                lv = self._learn_visit
                now = time.monotonic()
                if (
                    lv is not None
                    and not lv.get("closed")
                    and lv.get("until") is not None
                    and now >= lv["until"]
                    and not lv.get("person_present")
                ):
                    lv["closed"] = True
                    try:
                        await self._finalize_learn_visit(lv)
                    except Exception as exc:
                        logger.exception("Learn visit finalize failed: %s", exc)
                    finally:
                        self._learn_visit = None

                # Apply recent human labels → detector gets smarter.
                await self._apply_learn_feedback()
            except Exception as exc:
                logger.exception("Learn poll error: %s", exc)

            await asyncio.sleep(5)

    async def _start_learn_session(self, session_id: str | None) -> None:
        if not session_id:
            logger.warning("learn_mode on but learn_session_id mangler")
            return
        self._learn_active = True
        self._learn_session_id = session_id
        self._learn_frames = []
        self._learn_paths = []
        self._learn_chunk_started = 0.0
        self._learn_last_push = 0.0
        self._learn_started_wall = datetime.now(timezone.utc)
        self._learn_finalizing = False
        self._learn_visit = None
        STATE.push_feed(
            [
                {
                    "id": f"learn-on-{session_id[:8]}",
                    "status": "scan",
                    "text": "Opplæring PÅ — gå foran kameraet og kast riktig + feil",
                }
            ]
        )
        logger.info("Learn session started: %s", session_id)
        if self._repo:
            await self._repo.patch_learn_session(session_id, status="recording")

    async def _stop_learn_session(self) -> None:
        if self._learn_finalizing:
            return
        self._learn_finalizing = True
        session_id = self._learn_session_id
        logger.info("Learn session stopping: %s", session_id)
        STATE.push_feed(
            [
                {
                    "id": f"learn-off-{(session_id or 'x')[:8]}",
                    "status": "ok",
                    "text": "Opplæring STOPP — lagrer siste besøk…",
                }
            ]
        )
        try:
            # Flush active visit immediately.
            lv = self._learn_visit
            if lv is not None and not lv.get("closed"):
                lv["closed"] = True
                lv["person_present"] = False
                try:
                    await self._finalize_learn_visit(lv)
                except Exception as exc:
                    logger.exception("Final learn visit failed: %s", exc)
                self._learn_visit = None

            if self._repo and session_id:
                duration = None
                if self._learn_started_wall:
                    duration = (
                        datetime.now(timezone.utc) - self._learn_started_wall
                    ).total_seconds()
                main_path = self._learn_paths[-1] if self._learn_paths else None
                await self._repo.patch_learn_session(
                    session_id,
                    status="ready" if self._learn_paths else "failed",
                    dropbox_video_path=main_path,
                    dropbox_paths=list(self._learn_paths),
                    duration_seconds=duration,
                    chunk_count=len(self._learn_paths),
                    error_message=None
                    if self._learn_paths
                    else "Ingen besøk tatt opp — stå foran kameraet under opplæring",
                    stopped_at=datetime.now(timezone.utc),
                )
                cam_id = self._settings.vision_camera_db_id
                if cam_id:
                    await self._repo.clear_camera_learn_session(cam_id)
        except Exception as exc:
            logger.exception("Learn stop failed: %s", exc)
            if self._repo and session_id:
                await self._repo.patch_learn_session(
                    session_id,
                    status="failed",
                    error_message=str(exc)[:500],
                    stopped_at=datetime.now(timezone.utc),
                )
        finally:
            self._learn_active = False
            self._learn_session_id = None
            self._learn_frames = []
            self._learn_chunk_started = 0.0
            self._learn_finalizing = False
            STATE.push_feed(
                [
                    {
                        "id": f"learn-done-{int(time.time())}",
                        "status": "ok",
                        "text": "Opplæring ferdig — merk riktig/feil i DriftPro",
                    }
                ]
            )

    async def _apply_learn_feedback(self) -> None:
        """Les nyeste merker og juster detector-terskel / klasser."""
        if not self._repo or not hasattr(self._detector, "apply_learn_feedback"):
            return
        try:
            labels = await self._repo.fetch_recent_learn_labels(limit=80)
            if not labels:
                return
            self._detector.apply_learn_feedback(labels)  # type: ignore[union-attr]
        except Exception as exc:
            logger.debug("apply_learn_feedback: %s", exc)

    async def _flush_learn_chunk(self, *, final: bool) -> None:
        frames_raw = list(self._learn_frames)
        self._learn_frames = []
        self._learn_chunk_started = time.monotonic()
        if len(frames_raw) < 4:
            logger.warning("Learn chunk too short (%d frames)", len(frames_raw))
            return

        from frame_ring_buffer import BufferedFrame
        import cv2

        bufs: list[BufferedFrame] = []
        for frame in frames_raw:
            ok, encoded = cv2.imencode(
                ".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 70]
            )
            if not ok:
                continue
            h, w = frame.shape[:2]
            bufs.append(
                BufferedFrame(
                    t=time.monotonic(), jpeg=encoded.tobytes(), width=w, height=h
                )
            )
        if len(bufs) < 4:
            return

        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
        sid = (self._learn_session_id or "nosession")[:8]
        base = Path(self._settings.local_captures_dir) / (
            f"learn_{sid}_{stamp}_{len(self._learn_paths)}"
        )
        video_path = await asyncio.to_thread(
            write_clip_mp4,
            bufs,
            base,
            fps=self._settings.clip_fps,
        )

        if self._settings.local_dev and not self._company_dropbox:
            self._learn_paths.append(str(video_path))
            logger.info("Learn chunk local only: %s", video_path)
            return

        if not self._company_dropbox:
            logger.error("Learn chunk: no Dropbox — kept at %s", video_path)
            self._learn_paths.append(str(video_path))
            return

        video_bytes = await asyncio.to_thread(video_path.read_bytes)
        try:
            upload = await asyncio.to_thread(
                self._company_dropbox.upload_file,
                data=video_bytes,
                company_id=self._dropbox_company_id,
                file_name=(
                    f"learn_{self._settings.camera_id}_{sid}_"
                    f"{stamp}_part{len(self._learn_paths)}.mp4"
                ),
                category="vision_learn_clip",
            )
            self._learn_paths.append(upload.path)
            logger.info(
                "Learn chunk uploaded%s: %s",
                " (final)" if final else "",
                upload.path,
            )
            if self._repo and self._learn_session_id:
                await self._repo.patch_learn_session(
                    self._learn_session_id,
                    status="uploading" if final else "recording",
                    dropbox_paths=list(self._learn_paths),
                    chunk_count=len(self._learn_paths),
                    dropbox_video_path=upload.path,
                    dropbox_video_url=upload.share_url,
                )
        except Exception as exc:
            logger.exception("Learn chunk upload failed: %s", exc)
            self._learn_paths.append(str(video_path))

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
                company_id=self._dropbox_company_id,
                camera_id=self._settings.camera_id,
                event_type=self._settings.event_type.value,
                captured_at=captured_at,
            )
        else:
            upload = await asyncio.to_thread(
                self._dropbox.upload_jpeg,  # type: ignore[union-attr]
                image_bytes=image_bytes,
                company_id=self._dropbox_company_id,
                camera_id=self._settings.camera_id,
                event_type=self._settings.event_type.value,
                captured_at=captured_at,
            )

        record = VisionEventRecord(
            company_id=self._event_company_id,
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
