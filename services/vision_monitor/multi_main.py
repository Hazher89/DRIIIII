#!/usr/bin/env python3
"""Run one pipeline per camera (Supabase list or .env fallback)."""

from __future__ import annotations

import asyncio
import logging
import signal

from config import Settings
from pipeline import VisionMonitorPipeline
from supabase_cameras import camera_config_from_env, load_cameras_from_supabase

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("vision_monitor.multi")


async def _main() -> None:
    base_settings = Settings.from_env()
    if base_settings.local_dev:
        from local_server import start_local_server

        start_local_server(
            base_settings.local_server_port,
            captures_dir=base_settings.local_captures_dir,
        )

    cameras = await load_cameras_from_supabase(base_settings)
    if not cameras:
        cameras = [camera_config_from_env(base_settings)]
        logger.info("Using single camera from .env")

    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()

    def _shutdown() -> None:
        logger.info("Shutdown requested")
        stop_event.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, _shutdown)

    pipelines: list[VisionMonitorPipeline] = []
    for cam in cameras:
        settings = Settings(
            camera_url=cam.camera_url,
            camera_host=cam.camera_host,
            camera_user=cam.camera_user,
            camera_password=cam.camera_password,
            camera_mode=base_settings.camera_mode,
            camera_id=cam.camera_id,
            company_id=cam.company_id,
            supabase_url=base_settings.supabase_url,
            supabase_service_role_key=base_settings.supabase_service_role_key,
            dropbox_access_token=base_settings.dropbox_access_token,
            dropbox_root_folder=base_settings.dropbox_root_folder,
            yolo_model=base_settings.yolo_model,
            event_type=cam.event_type,
            confidence_threshold=base_settings.confidence_threshold,
            entry_cooldown_seconds=base_settings.entry_cooldown_seconds,
            frame_skip=base_settings.frame_skip,
            jpeg_quality=base_settings.jpeg_quality,
            local_dev=base_settings.local_dev,
            local_captures_dir=base_settings.local_captures_dir,
            local_server_port=base_settings.local_server_port,
            snapshot_interval_ms=base_settings.snapshot_interval_ms,
        )
        pipelines.append(VisionMonitorPipeline(settings))

    tasks = [asyncio.create_task(p.run()) for p in pipelines]
    await stop_event.wait()

    for p in pipelines:
        await p.stop()
    for t in tasks:
        t.cancel()
    await asyncio.gather(*tasks, return_exceptions=True)
    logger.info("All camera pipelines stopped")


if __name__ == "__main__":
    asyncio.run(_main())
