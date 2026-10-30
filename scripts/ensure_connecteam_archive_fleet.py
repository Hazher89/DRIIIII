#!/usr/bin/env python3
"""Opprett Connecteam-arkiv-partner + inaktive MAVI-biler for historiske PDF-er.

Bruk:
  SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \\
    python3 scripts/ensure_connecteam_archive_fleet.py \\
      --from-import-log exports/connecteam_pdfs/import_log.csv
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
import urllib.request
from pathlib import Path

COMPANY = "00000000-0000-0000-0000-000000000000"
ARCHIVE_NAME = "Connecteam Arkiv (historikk)"
UA = "driftpro-archive-fleet/1.0"


def normalize_mavi(raw: str) -> str:
    s = re.sub(r"\s+", "", (raw or "").strip().upper())
    m = re.fullmatch(r"NO_O_M0*(\d{1,5})", s) or re.fullmatch(r"M0*(\d{1,5})", s)
    if m:
        return f"NO_O_M{int(m.group(1)):04d}"
    return s


class Supa:
    def __init__(self, url: str, key: str) -> None:
        self.url = url.rstrip("/")
        self.key = key
        self.h = {
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": UA,
        }

    def rest(self, path: str, *, method: str = "GET", body=None, prefer: str | None = None):
        headers = dict(self.h)
        if prefer:
            headers["Prefer"] = prefer
        data = json.dumps(body).encode() if body is not None else None
        last = None
        for attempt in range(5):
            try:
                req = urllib.request.Request(
                    self.url + path, data=data, headers=headers, method=method
                )
                with urllib.request.urlopen(req, timeout=120) as r:
                    raw = r.read().decode()
                    return json.loads(raw) if raw else None
            except Exception as e:
                last = e
                time.sleep(1.2 * (attempt + 1))
        raise last  # type: ignore


def collect_mavis_from_log(path: Path) -> set[str]:
    out: set[str] = set()
    with path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row.get("status") != "skipped_no_vehicle":
                continue
            m = (row.get("mavi") or "").strip()
            if not m:
                continue
            n = normalize_mavi(m)
            if n.startswith("NO_O_M"):
                out.add(n)
    return out


def collect_mavis_from_disk(root: Path) -> set[str]:
    out: set[str] = set()
    for p in root.rglob("*"):
        if p.suffix.lower() != ".pdf":
            continue
        for pat in (
            r"NO_O_M0*(\d{1,5})",
            r"[_\-\.]M0*(\d{1,5})(?=[_\-\.]|\.PDF|$)",
            r"MAVI[_\s-]*(\d{1,5})",
        ):
            m = re.search(pat, p.name, re.I)
            if m:
                out.add(normalize_mavi(f"M{int(m.group(1))}"))
                break
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--from-import-log", default="exports/connecteam_pdfs/import_log.csv")
    ap.add_argument("--scan-disk", default="")
    ap.add_argument("--company-id", default=COMPANY)
    args = ap.parse_args()

    url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not url or not key:
        print("Sett SUPABASE_URL og SUPABASE_SERVICE_ROLE_KEY", file=sys.stderr)
        return 2

    sb = Supa(url, key)
    mavis: set[str] = set()
    log = Path(args.from_import_log)
    if log.is_file():
        mavis |= collect_mavis_from_log(log)
    if args.scan_disk:
        mavis |= collect_mavis_from_disk(Path(args.scan_disk))

    print(f"Unike MAVI fra hoppet-over / disk: {len(mavis)}")

    # Existing active fleet MAVIs — skip creating archive for those
    active = sb.rest(
        f"/rest/v1/partner_vehicles?company_id=eq.{args.company_id}"
        f"&vehicle_kind=eq.mavi&is_active=eq.true&select=unit_code&limit=500"
    ) or []
    active_norm = {normalize_mavi(v.get("unit_code") or "") for v in active}
    needed = sorted(m for m in mavis if m and m not in active_norm)
    print(f"Trenger arkiv-bil (ikke aktiv i flåte): {len(needed)}")

    partners = sb.rest(
        f"/rest/v1/partners?company_id=eq.{args.company_id}"
        f"&name=eq.{urllib_quote(ARCHIVE_NAME)}&select=id,name&limit=1"
    ) or []
    if partners:
        partner_id = partners[0]["id"]
        print(f"Arkiv-partner finnes: {partner_id}")
    else:
        created = sb.rest(
            "/rest/v1/partners",
            method="POST",
            body={
                "company_id": args.company_id,
                "name": ARCHIVE_NAME,
                "is_active": True,
                "portal_access": False,
                "workforce_enabled": False,
                "notes": (
                    "Historiske Connecteam-ruter for MAVI som ikke er aktive i "
                    "dagens flåte. Kun arkiv og PDF-søk — ikke planlegging/SMS."
                ),
            },
            prefer="return=representation",
        )
        if not isinstance(created, list) or not created:
            print("Kunne ikke opprette arkiv-partner", file=sys.stderr)
            return 1
        partner_id = created[0]["id"]
        print(f"Opprettet arkiv-partner: {partner_id}")

    existing = sb.rest(
        f"/rest/v1/partner_vehicles?partner_id=eq.{partner_id}"
        f"&select=id,unit_code&limit=1000"
    ) or []
    have = {normalize_mavi(v.get("unit_code") or "") for v in existing}
    created_n = 0
    for code in needed:
        if code in have:
            continue
        sb.rest(
            "/rest/v1/partner_vehicles",
            method="POST",
            body={
                "company_id": args.company_id,
                "partner_id": partner_id,
                "unit_code": code,
                "registration_number": "—",
                "vehicle_kind": "mavi",
                "is_active": False,
                "fleet_roles": ["intern"],
                "notes": "Connecteam-arkiv: historisk MAVI (ikke aktiv)",
                "driver_name": f"Arkiv {code}",
            },
            prefer="return=minimal",
        )
        created_n += 1
        have.add(code)
        if created_n % 10 == 0:
            print(f"  …opprettet {created_n}")
        time.sleep(0.03)

    print(f"Ferdig. Nye arkiv-biler: {created_n}. Totalt i arkiv-partner: {len(have)}")
    print(f"PARTNER_ID={partner_id}")
    return 0


def urllib_quote(s: str) -> str:
    from urllib.parse import quote

    return quote(s, safe="")


if __name__ == "__main__":
    raise SystemExit(main())
