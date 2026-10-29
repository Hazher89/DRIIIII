#!/usr/bin/env python3
"""
Last ned alle PDF-vedlegg fra Connecteam Job Scheduler («RUTER TILDELT»).

Bruk:
  export CONNECTEAM_API_KEY='din-nøkkel'
  python3 scripts/connecteam_export_pdfs.py --from 2024-01 --to 2026-10

Valgfritt:
  --scheduler-id 6213032
  --out exports/connecteam_pdfs
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

API_BASE = "https://api.connecteam.com"
UA = "DriftPro-ConnecteamExport/1.0"


def month_range(ym: str) -> tuple[int, int]:
    y, m = map(int, ym.split("-"))
    start = datetime(y, m, 1, tzinfo=timezone.utc)
    if m == 12:
        end = datetime(y + 1, 1, 1, tzinfo=timezone.utc)
    else:
        end = datetime(y, m + 1, 1, tzinfo=timezone.utc)
    return int(start.timestamp()), int(end.timestamp())


def iter_months(from_ym: str, to_ym: str) -> list[str]:
    y, m = map(int, from_ym.split("-"))
    y2, m2 = map(int, to_ym.split("-"))
    out: list[str] = []
    while (y, m) <= (y2, m2):
        out.append(f"{y:04d}-{m:02d}")
        m += 1
        if m > 12:
            m = 1
            y += 1
    return out


def api_get(path: str, key: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
    q = urllib.parse.urlencode(params or {}, doseq=True)
    url = f"{API_BASE}{path}" + (f"?{q}" if q else "")
    req = urllib.request.Request(
        url,
        headers={
            "X-API-KEY": key,
            "Accept": "application/json",
            "User-Agent": UA,
        },
    )
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            if e.code in (429, 500, 502, 503, 504) and attempt < 4:
                time.sleep(2 ** attempt)
                continue
            raise RuntimeError(f"HTTP {e.code} {url}: {body[:400]}") from e
    raise RuntimeError(f"Failed GET {url}")


def list_schedulers(key: str) -> list[dict[str, Any]]:
    data = api_get("/scheduler/v1/schedulers", key)
    return list(data.get("data", {}).get("schedulers") or [])


def fetch_shifts(
    key: str, scheduler_id: int, start: int, end: int
) -> list[dict[str, Any]]:
    offset = 0
    all_shifts: list[dict[str, Any]] = []
    while True:
        data = api_get(
            f"/scheduler/v1/schedulers/{scheduler_id}/shifts",
            key,
            {
                "startTime": start,
                "endTime": end,
                "limit": 500,
                "offset": offset,
            },
        )
        batch = list(data.get("data", {}).get("shifts") or [])
        if not batch:
            break
        all_shifts.extend(batch)
        offset += len(batch)
        if len(batch) < 500:
            break
        time.sleep(0.15)
    return all_shifts


def safe_name(s: str) -> str:
    s = re.sub(r"[^\w.\-æøåÆØÅ]+", "_", s.strip(), flags=re.UNICODE)
    return s.strip("_")[:120] or "fil"


def pdf_notes(shift: dict[str, Any]) -> list[dict[str, Any]]:
    out = []
    for n in shift.get("notes") or []:
        if n.get("type") != "file":
            continue
        name = str(n.get("name") or "")
        url = str(n.get("url") or "")
        if not url:
            continue
        if name.lower().endswith(".pdf") or url.lower().split("?")[0].endswith(".pdf"):
            out.append(n)
    return out


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=120) as r, open(tmp, "wb") as f:
        while True:
            chunk = r.read(1024 * 256)
            if not chunk:
                break
            f.write(chunk)
    tmp.replace(dest)


def main() -> int:
    p = argparse.ArgumentParser(description="Eksporter Connecteam rute-PDF-er")
    p.add_argument("--from", dest="from_ym", default="2024-01", help="YYYY-MM")
    p.add_argument("--to", dest="to_ym", default=datetime.now().strftime("%Y-%m"))
    p.add_argument("--scheduler-id", type=int, default=0)
    p.add_argument("--out", default="exports/connecteam_pdfs")
    p.add_argument("--list-schedulers", action="store_true")
    args = p.parse_args()

    key = os.environ.get("CONNECTEAM_API_KEY", "").strip()
    if not key:
        print(
            "Sett CONNECTEAM_API_KEY i miljøet først.\n"
            "  export CONNECTEAM_API_KEY='...'\n"
            "Ikke lim nøkkelen inn i git/kode.",
            file=sys.stderr,
        )
        return 2

    schedulers = list_schedulers(key)
    if args.list_schedulers or not args.scheduler_id:
        print("Tilgjengelige scheduler:")
        for s in schedulers:
            print(
                f"  id={s.get('schedulerId')}  "
                f"name={s.get('name')!r}  archived={s.get('isArchived')}"
            )
        if args.list_schedulers:
            return 0

    sid = args.scheduler_id
    if not sid:
        # Prefer «RUTER TILDELT»
        for s in schedulers:
            if str(s.get("name", "")).strip().upper() == "RUTER TILDELT":
                sid = int(s["schedulerId"])
                break
        if not sid and schedulers:
            sid = int(schedulers[0]["schedulerId"])
    if not sid:
        print("Fant ingen scheduler.", file=sys.stderr)
        return 1

    out_root = Path(args.out)
    out_root.mkdir(parents=True, exist_ok=True)
    manifest_path = out_root / "manifest.csv"
    write_header = not manifest_path.exists()

    months = iter_months(args.from_ym, args.to_ym)
    print(f"Scheduler {sid} · {len(months)} måneder · output {out_root}")

    total_files = 0
    total_downloaded = 0
    total_skipped = 0

    with open(manifest_path, "a", newline="", encoding="utf-8") as mf:
        w = csv.DictWriter(
            mf,
            fieldnames=[
                "month",
                "shift_id",
                "start_local",
                "title",
                "user_ids",
                "file_name",
                "saved_as",
                "url",
                "status",
            ],
        )
        if write_header:
            w.writeheader()

        for ym in months:
            start, end = month_range(ym)
            print(f"\n=== {ym} ===")
            try:
                shifts = fetch_shifts(key, sid, start, end)
            except Exception as e:
                print(f"FEIL {ym}: {e}", file=sys.stderr)
                continue

            month_dir = out_root / ym
            month_pdfs = 0
            for s in shifts:
                for n in pdf_notes(s):
                    total_files += 1
                    month_pdfs += 1
                    start_ts = int(s.get("startTime") or 0)
                    local = datetime.fromtimestamp(start_ts, tz=timezone.utc).astimezone()
                    day = local.strftime("%Y-%m-%d")
                    fname = safe_name(str(n.get("name") or "rute.pdf"))
                    if not fname.lower().endswith(".pdf"):
                        fname += ".pdf"
                    # Unik sti: dato_tittel_originalnavn (unngå overwrite)
                    shift_tail = safe_name(str(s.get("id", ""))[-12:])
                    saved = month_dir / f"{day}_{safe_name(str(s.get('title') or 'rute'))}_{shift_tail}_{fname}"
                    status = "downloaded"
                    try:
                        if saved.exists() and saved.stat().st_size > 100:
                            status = "skipped_exists"
                            total_skipped += 1
                        else:
                            download(str(n["url"]), saved)
                            total_downloaded += 1
                            time.sleep(0.05)
                    except Exception as e:
                        status = f"error:{e}"
                        print(f"  feil {fname}: {e}", file=sys.stderr)

                    w.writerow(
                        {
                            "month": ym,
                            "shift_id": s.get("id"),
                            "start_local": local.isoformat(timespec="minutes"),
                            "title": s.get("title"),
                            "user_ids": ",".join(
                                str(u) for u in (s.get("assignedUserIds") or [])
                            ),
                            "file_name": n.get("name"),
                            "saved_as": str(saved.relative_to(out_root))
                            if saved.exists()
                            else "",
                            "url": n.get("url"),
                            "status": status,
                        }
                    )
            mf.flush()
            print(f"  skift={len(shifts)}  pdf={month_pdfs}")

    print(
        f"\nFerdig. PDF-treff={total_files}  "
        f"nedlastet={total_downloaded}  hoppet over={total_skipped}"
    )
    print(f"Manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
