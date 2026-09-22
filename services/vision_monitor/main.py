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


def _install_shutdown_handlers(stop_event: asyncio.Event) -> None:
    def _request_shutdown(*_args) -> None:
        logger.info("Shutdown requested")
        # Event.set() is thread-safe enough for Ctrl+C on Windows.
        stop_event.set()

    # Windows ProactorEventLoop does not support add_signal_handler.
    try:
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, _request_shutdown)
        logger.info("Using asyncio signal handlers (%s)", sys.platform)
    except (NotImplementedError, RuntimeError, AttributeError):
        signal.signal(signal.SIGINT, _request_shutdown)
        try:
            signal.signal(signal.SIGTERM, _request_shutdown)
        except (ValueError, OSError):
            pass
        logger.info("Using signal.signal handlers (%s)", sys.platform)


async def _main() -> None:
    settings = Settings.from_env()
    pipeline = VisionMonitorPipeline(settings)
    stop_event = asyncio.Event()
    _install_shutdown_handlers(stop_event)

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
