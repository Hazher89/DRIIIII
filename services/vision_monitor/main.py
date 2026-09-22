#!/usr/bin/env python3
"""DriftPro Vision Monitor — RTSP person entry → Dropbox snapshot → Supabase."""

from __future__ import annotations

import asyncio
import logging
import signal
import sys

from config import Settings
from pipeline import VisionMonitorPipeline

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("vision_monitor")


async def _main() -> None:
    settings = Settings.from_env()
    pipeline = VisionMonitorPipeline(settings)

    stop_event = asyncio.Event()

    def _request_shutdown(*_args) -> None:
        logger.info("Shutdown requested")
        stop_event.set()

    # asyncio.add_signal_handler is not supported on Windows.
    if sys.platform == "win32":
        signal.signal(signal.SIGINT, _request_shutdown)
        signal.signal(signal.SIGTERM, _request_shutdown)
    else:
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, _request_shutdown)

    run_task = asyncio.create_task(pipeline.run())
    await stop_event.wait()
    await pipeline.stop()
    run_task.cancel()
    try:
        await run_task
    except asyncio.CancelledError:
        pass

    logger.info("Vision monitor stopped")


if __name__ == "__main__":
    asyncio.run(_main())
