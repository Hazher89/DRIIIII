"""Re-encode existing sorting MP4s to H.264 and re-upload so DriftPro web can play them.

Run on Windows job PC (after git pull):
  .\\.venv\\Scripts\\pip install imageio-ffmpeg
  .\\.venv\\Scripts\\python.exe repair_clips.py
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import httpx
from dotenv import load_dotenv

from supabase_dropbox import SupabaseDropboxUpload
from video_clip import _ffmpeg_exe

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("repair_clips")

load_dotenv()


def _reencode_file(src: Path, dst: Path) -> None:
    ffmpeg = _ffmpeg_exe()
    cmd = [
        ffmpeg,
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        str(src),
        "-an",
        "-c:v",
        "libx264",
        "-preset",
        "veryfast",
        "-crf",
        "23",
        "-pix_fmt",
        "yuv420p",
        "-movflags",
        "+faststart",
        str(dst),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    if proc.returncode != 0 or not dst.is_file() or dst.stat().st_size < 1000:
        raise RuntimeError(f"ffmpeg failed: {proc.stderr[:400]}")


def main() -> int:
    supabase_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    company_id = os.environ.get("COMPANY_ID", "").strip()
    if not supabase_url or not key or not company_id:
        logger.error("Mangler SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / COMPANY_ID i .env")
        return 1

    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }

    uploader = SupabaseDropboxUpload(supabase_url, key)

    with httpx.Client(timeout=120.0) as client:
        res = client.get(
            f"{supabase_url}/rest/v1/vision_events"
            f"?event_type=eq.sorting_clip&order=created_at.desc&limit=30"
            f"&select=id,dropbox_path,dropbox_image_url,metadata,created_at",
            headers=headers,
        )
        if res.status_code >= 400:
            logger.error("Kunne ikke hente events: %s %s", res.status_code, res.text[:200])
            return 1
        events = res.json()

    if not events:
        logger.info("Ingen sorting_clip events.")
        return 0

    ok = 0
    fail = 0
    for ev in events:
        eid = ev["id"]
        meta = ev.get("metadata") or {}
        if isinstance(meta, str):
            meta = json.loads(meta)
        path = meta.get("dropbox_video_path") or ev.get("dropbox_path") or ""
        if not path or not str(path).lower().endswith(".mp4"):
            logger.info("Hopper over %s (ingen mp4-sti)", eid[:8])
            continue
        if meta.get("codec") == "h264":
            logger.info("Allerede h264: %s", eid[:8])
            continue

        logger.info("Reparerer %s … %s", eid[:8], path)
        try:
            with httpx.Client(timeout=180.0) as client:
                auth_res = client.post(
                    f"{supabase_url}/functions/v1/vision-camera?action=dropbox_auth",
                    headers=headers,
                    json={
                        "company_id": company_id,
                        "file_name": Path(str(path)).name,
                        "category": "vision_sorting_clip",
                    },
                )
                auth_res.raise_for_status()
                token = auth_res.json()["access_token"]

                dropbox_path = str(path)
                if not dropbox_path.startswith("/"):
                    dropbox_path = f"/{dropbox_path}"

                link_res = client.post(
                    "https://api.dropboxapi.com/2/files/get_temporary_link",
                    headers={
                        "Authorization": f"Bearer {token}",
                        "Content-Type": "application/json",
                    },
                    json={"path": dropbox_path},
                )
                link_res.raise_for_status()
                tmp_url = link_res.json()["link"]

                raw = client.get(tmp_url)
                raw.raise_for_status()
                data = raw.content

            with tempfile.TemporaryDirectory() as td:
                src = Path(td) / "in.mp4"
                dst = Path(td) / "out.mp4"
                src.write_bytes(data)
                _reencode_file(src, dst)
                new_bytes = dst.read_bytes()

            upload = uploader.upload_file(
                data=new_bytes,
                company_id=company_id,
                file_name=f"repaired_{Path(str(path)).name}",
                category="vision_sorting_clip",
            )
            meta = dict(meta)
            meta["dropbox_video_path"] = upload.path
            meta["dropbox_video_url"] = upload.share_url
            meta["codec"] = "h264"
            meta["repaired"] = True

            with httpx.Client(timeout=60.0) as client:
                patch = client.patch(
                    f"{supabase_url}/rest/v1/vision_events?id=eq.{eid}",
                    headers=headers,
                    json={
                        "dropbox_path": upload.path,
                        "metadata": meta,
                    },
                )
                if patch.status_code >= 400:
                    raise RuntimeError(
                        f"patch failed: {patch.status_code} {patch.text[:200]}"
                    )

            logger.info("OK %s → %s", eid[:8], upload.path)
            ok += 1
        except Exception as exc:  # noqa: BLE001
            logger.exception("Feilet %s: %s", eid[:8], exc)
            fail += 1

    captures = Path("captures")
    if captures.is_dir():
        for mp4 in sorted(captures.glob("*.mp4")):
            if mp4.name.endswith("_h264.mp4"):
                continue
            out = mp4.with_name(mp4.stem + "_h264.mp4")
            if out.exists():
                continue
            try:
                logger.info("Lokal re-encode: %s", mp4.name)
                _reencode_file(mp4, out)
            except Exception as exc:  # noqa: BLE001
                logger.warning("Lokal feilet %s: %s", mp4.name, exc)

    logger.info("Ferdig. reparert=%d feilet=%d", ok, fail)
    return 0 if fail == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
