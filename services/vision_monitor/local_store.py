"""Local dev storage when Dropbox/Supabase are not configured."""

from __future__ import annotations

import json
import logging
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class LocalEvent:
    id: str
    timestamp: str
    camera_id: str
    event_type: str
    status: str
    image_url: str
    image_path: str
    metadata: dict[str, Any]

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


class LocalEventStore:
    def __init__(self, captures_dir: str) -> None:
        self._dir = Path(captures_dir)
        self._dir.mkdir(parents=True, exist_ok=True)
        self._events_file = self._dir / "events.json"
        self._events: list[dict[str, Any]] = []
        if self._events_file.exists():
            try:
                self._events = json.loads(self._events_file.read_text())
            except json.JSONDecodeError:
                self._events = []

    def save_snapshot(self, image_bytes: bytes, *, camera_id: str, event_type: str) -> tuple[str, Path]:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%f")
        filename = f"{stamp}_{camera_id}_{event_type}.jpg"
        path = self._dir / filename
        path.write_bytes(image_bytes)
        return filename, path

    def append_event(self, event: LocalEvent) -> dict[str, Any]:
        row = event.to_dict()
        self._events.insert(0, row)
        self._events = self._events[:500]
        self._events_file.write_text(json.dumps(self._events, indent=2))
        return row

    @property
    def events(self) -> list[dict[str, Any]]:
        return list(self._events)
