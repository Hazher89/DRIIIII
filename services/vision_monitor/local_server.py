"""In-memory state + local HTTP dashboard for dev."""

from __future__ import annotations

import json
import logging
import threading
import time
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

import cv2
import numpy as np

logger = logging.getLogger(__name__)


@dataclass
class MonitorState:
    latest_frame: np.ndarray | None = None
    latest_jpeg: bytes | None = None
    frame_index: int = 0
    events: list[dict[str, Any]] = field(default_factory=list)
    camera_url: str = ""
    camera_mode: str = ""
    status: str = "starting"
    persons_visible: int = 0
    scanning_active: bool = False
    feed_lines: list[dict[str, Any]] = field(default_factory=list)
    lock: threading.Lock = field(default_factory=threading.Lock)

    def set_scan(self, persons: int, *, active: bool) -> None:
        with self.lock:
            self.persons_visible = persons
            self.scanning_active = active

    def set_frame(self, frame: np.ndarray, *, frame_index: int | None = None) -> None:
        ok, encoded = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 80])
        with self.lock:
            self.latest_frame = frame
            self.latest_jpeg = encoded.tobytes() if ok else None
            if frame_index is not None:
                self.frame_index = frame_index

    def copy_latest_frame(self) -> tuple[np.ndarray | None, int]:
        with self.lock:
            if self.latest_frame is None:
                return None, self.frame_index
            return self.latest_frame.copy(), self.frame_index

    def add_event(self, event: dict[str, Any]) -> None:
        with self.lock:
            self.events.insert(0, event)
            self.events = self.events[:100]

    def hydrate_events(self, rows: list[dict[str, Any]]) -> None:
        with self.lock:
            self.events = list(rows[:100])

    def clear_events(self) -> None:
        with self.lock:
            self.events.clear()

    def push_feed(self, lines: list[dict[str, Any]]) -> None:
        if not lines:
            return
        with self.lock:
            for line in lines:
                row = dict(line)
                row["ts"] = time.time()
                self.feed_lines.insert(0, row)
            self.feed_lines = self.feed_lines[:50]

    def snapshot_feed(self) -> list[dict[str, Any]]:
        with self.lock:
            return list(self.feed_lines)

    def snapshot(self) -> tuple[bytes | None, list[dict[str, Any]], dict[str, str]]:
        with self.lock:
            return self.latest_jpeg, list(self.events), {
                "status": self.status,
                "camera_url": self.camera_url,
                "camera_mode": self.camera_mode,
                "persons_visible": self.persons_visible,
                "scanning_active": self.scanning_active,
                "violations_session": len(self.events),
                "frame_index": self.frame_index,
            }


STATE = MonitorState()
CAPTURES_DIR = "captures"


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args: Any) -> None:  # noqa: A003
        logger.debug(format, *args)

    def _send_cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self._send_cors()
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path in {"/", "/index.html"}:
            self._html()
        elif path == "/api/status":
            self._json_status()
        elif path == "/api/events":
            self._json_events()
        elif path == "/api/events/clear":
            self._clear_events()
        elif path == "/api/scan":
            self._json_scan()
        elif path == "/api/feed":
            self._json_feed()
        elif path in {"/embed", "/live"}:
            self._embed_live()
        elif path == "/live.jpg":
            self._jpeg()
        elif path == "/live.mjpeg":
            self._mjpeg_stream()
        elif path.startswith("/captures/"):
            self._capture_file()
        else:
            self.send_error(404)

    def _html(self) -> None:
        body = """<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>DriftPro Vision Monitor</title>
<meta http-equiv="refresh" content="2">
<style>
body{font-family:system-ui;background:#111;color:#eee;margin:24px}
.card{background:#1e1e1e;border-radius:12px;padding:16px;margin-bottom:16px}
img{max-width:100%;border-radius:8px;border:2px solid #2e7d32}
table{width:100%;border-collapse:collapse}td,th{padding:8px;border-bottom:1px solid #333;text-align:left}
.ok{color:#66bb6a}.warn{color:#ffb74d}
</style></head><body>
<h1>DriftPro Vision Monitor</h1>
<div class="card"><h2>Live</h2>
<p id="status">Laster…</p>
<img src="/live.jpg" alt="live" onerror="this.style.opacity=0.3"></div>
<div class="card"><h2>Hendelser</h2><div id="events">Laster…</div></div>
<script>
fetch('/api/status').then(r=>r.json()).then(s=>{
  document.getElementById('status').innerHTML =
    `<span class="ok">${s.status}</span> · ${s.camera_mode} · <code>${s.camera_url}</code>`;
});
fetch('/api/events').then(r=>r.json()).then(rows=>{
  if(!rows.length){document.getElementById('events').textContent='Ingen hendelser ennå';return}
  let h='<table><tr><th>Tid</th><th>Type</th><th>SSCC/track</th><th>Bilde</th></tr>';
  for(const e of rows){
    h+=`<tr><td>${e.timestamp}</td><td>${e.event_type}</td><td>${e.metadata?.track_id??'-'}</td>
    <td><a href="${e.image_url}">vis</a></td></tr>`}
  document.getElementById('events').innerHTML=h+'</table>';
});
</script></body></html>"""
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(body.encode())

    def _json_status(self) -> None:
        _, _, meta = STATE.snapshot()
        self._send_json(meta)

    def _json_events(self) -> None:
        _, events, _ = STATE.snapshot()
        self._send_json(events)

    def _clear_events(self) -> None:
        from pathlib import Path

        STATE.clear_events()
        events_file = Path(CAPTURES_DIR) / "events.json"
        events_file.write_text("[]")
        self._send_json({"ok": True, "count": 0})

    def _jpeg(self) -> None:
        jpeg, _, _ = STATE.snapshot()
        if not jpeg:
            self.send_error(503, "No frame yet")
            return
        self.send_response(200)
        self.send_header("Content-Type", "image/jpeg")
        self.send_header("Cache-Control", "no-store")
        self._send_cors()
        self.end_headers()
        self.wfile.write(jpeg)

    def _capture_file(self) -> None:
        from pathlib import Path

        name = self.path.removeprefix("/captures/").split("?")[0]
        if ".." in name or "/" in name:
            self.send_error(400)
            return
        path = Path(CAPTURES_DIR) / name
        if not path.is_file():
            self.send_error(404)
            return
        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "image/jpeg")
        self.send_header("Cache-Control", "no-store")
        self._send_cors()
        self.end_headers()
        self.wfile.write(data)

    def _json_scan(self) -> None:
        _, events, meta = STATE.snapshot()
        self._send_json({
            "active": meta.get("scanning_active", False),
            "persons": meta.get("persons_visible", 0),
            "status": meta.get("status", ""),
            "violations_session": meta.get("violations_session", len(events)),
        })

    def _json_feed(self) -> None:
        self._send_json(STATE.snapshot_feed())

    def _embed_live(self) -> None:
        """Kun kamerabilde — MJPEG-strøm uten JavaScript."""
        body = """<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Live</title>
<style>
html,body{margin:0;height:100%;background:#000;overflow:hidden}
img{width:100%;height:100%;object-fit:cover;display:block}
</style></head><body>
<img src="/live.mjpeg" alt="Live">
</body></html>"""
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self._send_cors()
        self.end_headers()
        self.wfile.write(body.encode())

    def _mjpeg_stream(self) -> None:
        """multipart/x-mixed-replace — ekte live-følelse i nettleser."""
        boundary = b"--frame"
        self.send_response(200)
        self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        self._send_cors()
        self.end_headers()
        last_index = -1
        try:
            while True:
                jpeg, _, meta = STATE.snapshot()
                frame_index = int(meta.get("frame_index", 0))
                if jpeg:
                    last_index = frame_index
                    self.wfile.write(boundary + b"\r\n")
                    self.wfile.write(b"Content-Type: image/jpeg\r\n")
                    self.wfile.write(f"Content-Length: {len(jpeg)}\r\n\r\n".encode())
                    self.wfile.write(jpeg)
                    self.wfile.write(b"\r\n")
                    self.wfile.flush()
                time.sleep(0.12)
        except (BrokenPipeError, ConnectionResetError, OSError):
            return

    def _send_json(self, data: Any) -> None:
        payload = json.dumps(data).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self._send_cors()
        self.end_headers()
        self.wfile.write(payload)


_server_started = False


def start_local_server(port: int, *, captures_dir: str = "captures") -> ThreadingHTTPServer | None:
    global CAPTURES_DIR, _server_started  # noqa: PLW0603
    if _server_started:
        return None
    CAPTURES_DIR = captures_dir
    server = ThreadingHTTPServer(("0.0.0.0", port), _Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    _server_started = True
    logger.info("Local dashboard: http://127.0.0.1:%s", port)
    return server
