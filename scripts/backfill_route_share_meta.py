#!/usr/bin/env python3
"""
Fyll inn FO / sjåfør / kunder / område i partner_route_shares.notes
fra pdf_search_text (for ruter der auto-notater mangler felt).

  export SUPABASE_URL=…
  export SUPABASE_SERVICE_ROLE_KEY=…
  python3 scripts/backfill_route_share_meta.py [--limit 200] [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from typing import Any

COMPANY = "00000000-0000-0000-0000-000000000000"

# Speil av PostalRegionMapper (forenklet) — postnr→område via sted i tekst.
REGION_WORDS = {
    "oslo": "Oslo",
    "bærum": "Bærum",
    "baerum": "Bærum",
    "sandvika": "Bærum",
    "asker": "Bærum",
    "nesodden": "Nesodden",
    "ski": "Ski",
    "langhus": "Ski",
    "drammen": "Drammen",
    "jessheim": "Jessheim",
    "nittedal": "Nittedal",
    "hønefoss": "Hønefoss",
    "honefoss": "Hønefoss",
    "kongsvinger": "Kongsvinger",
    "moss": "Østfold",
    "sarpsborg": "Østfold",
    "fredrikstad": "Østfold",
    "halden": "Østfold",
    "askim": "Østfold",
    "østfold": "Østfold",
    "ostfold": "Østfold",
    "lillestrøm": "Indre",
    "lillestrom": "Indre",
    "lørenskog": "Indre",
    "lorenskog": "Indre",
    "strømmen": "Indre",
    "strommen": "Indre",
}


def parse_fo(text: str) -> str | None:
    m = re.search(r"Freight\s*Order\s*[:#]?\s*(\d{6,14})", text, re.I)
    if m:
        return m.group(1)
    m = re.search(r"\bF\d{3,5}(61\d{8,12})\b", text, re.I)
    return m.group(1) if m else None


def parse_driver(text: str) -> str | None:
    m = re.search(
        r"Driver\s*Name\s*([A-Za-zÆØÅæøå][A-Za-zÆØÅæøå0-9\s.\-]{0,80}?)"
        r"(?=Consumed|Contact|Email|Phone|Notes|Seq\b|Resource|Freight|Total|HUB|\d{2,4}\.\d{2}\s*KG|$)",
        text,
        re.I,
    )
    if not m:
        m = re.search(
            r"Driver\s*Name\s*(?:\r?\n\s*)?([A-Za-zÆØÅæøå][^\n]{1,60})",
            text,
            re.I,
        )
    if not m:
        return None
    s = m.group(1).strip()
    s = re.sub(
        r"(Consumed|Contact|Email|Phone|Notes|Weight|HUB|Seq\b).*$",
        "",
        s,
        flags=re.I,
    ).strip()
    dm = re.match(r"^(.+?)\s+(\d{2,4})\s+\2\s+\1\b", s, re.I)
    if dm:
        s = dm.group(1).strip()
    else:
        s = re.sub(r"\s+\d{2,4}(\s+\d{2,4})*\s*", " ", s).strip()
    parts = [p.capitalize() for p in s.split() if p and not p.isdigit()]
    return " ".join(parts) if parts else None


def parse_stops(text: str) -> list[tuple[str | None, str]]:
    """Return [(postal, place_hint), ...] from Trip Overview lines."""
    flat = re.sub(r"[\r\n]+", " ", text)
    stops: list[tuple[str | None, str]] = []
    for m in re.finditer(
        r"(\d+)\s+(\d{8,12}(?:\s*,\s*\d{8,12})*)\s+(.+?),?\s*\+47\s*\(?(\d{8})\)?",
        flat,
        re.I,
    ):
        rest = m.group(3)
        pm = re.search(r"(\d{4})\s+([A-Za-zÆØÅæøå][A-Za-zÆØÅæøå\s.-]{1,30})", rest)
        postal = pm.group(1) if pm else None
        place = pm.group(2).strip() if pm else rest
        # skip hub-ish
        if postal and postal.startswith("0484"):
            continue
        stops.append((postal, place))
    return stops


def region_for_place(place: str) -> str | None:
    s = place.lower().replace("æ", "ae").replace("ø", "o").replace("å", "aa")
    for key, region in REGION_WORDS.items():
        kn = key.replace("æ", "ae").replace("ø", "o").replace("å", "aa")
        if re.search(rf"\b{re.escape(kn)}\b", s):
            return region
    return None


def dominant_region(stops: list[tuple[str | None, str]]) -> tuple[str | None, int]:
    counts: Counter[str] = Counter()
    for postal, place in stops:
        r = region_for_place(place)
        if r:
            counts[r] += 1
    if not counts:
        return None, 0
    region, n = counts.most_common(1)[0]
    return region, n


def rebuild_notes(
    old: str | None,
    *,
    fo: str | None,
    driver: str | None,
    customers: int,
    region: str | None,
    region_n: int,
) -> str:
    lines = [ln.strip() for ln in (old or "").splitlines() if ln.strip()]
    keep: list[str] = []
    for ln in lines:
        if re.match(
            r"^(FO:|Sjåfør\s*\(PDF\)|Kunder:|Omr[aå]de:|Rutedato\s*\(PDF\)|Skift\s*\(auto\))",
            ln,
            re.I,
        ):
            continue
        keep.append(ln)

    out: list[str] = []
    # Keep stowing first if present
    stowing = [ln for ln in keep if ln.lower().startswith("stowing")]
    other = [ln for ln in keep if not ln.lower().startswith("stowing")]
    out.extend(stowing)
    if fo:
        out.append(f"FO: {fo}")
    if driver:
        out.append(f"Sjåfør (PDF): {driver}")
    if customers > 0:
        out.append(f"Kunder: {customers}")
    # preserve rutedato/skift from old if present
    for ln in lines:
        if re.match(r"^Rutedato\s*\(PDF\)", ln, re.I):
            out.append(ln)
        if re.match(r"^Skift\s*\(auto\)", ln, re.I):
            # replace later if region changes
            pass
    # Kun sett område når flertall av stoppene peker samme vei (≥40 %).
    confident = (
        region
        and region_n > 0
        and customers > 0
        and region_n >= max(2, int(customers * 0.4 + 0.999))
    )
    if confident:
        out.append(f"Område: {region} ({region_n} stopp)")
    elif any(re.match(r"^Omr[aå]de:", ln, re.I) for ln in lines):
        for ln in lines:
            if re.match(r"^Omr[aå]de:", ln, re.I):
                out.append(ln)
            if re.match(r"^Skift\s*\(auto\)", ln, re.I):
                out.append(ln)
    out.extend(other)
    # dedupe while preserving order
    seen: set[str] = set()
    final: list[str] = []
    for ln in out:
        key = ln.lower()
        if key in seen:
            continue
        seen.add(key)
        final.append(ln)
    return "\n".join(final)


class Supa:
    def __init__(self, url: str, key: str) -> None:
        self.url = url.rstrip("/")
        self.h = {
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        }

    def get(self, path: str) -> Any:
        req = urllib.request.Request(self.url + path, headers=self.h)
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read().decode())

    def patch(self, path: str, body: dict[str, Any]) -> None:
        req = urllib.request.Request(
            self.url + path,
            data=json.dumps(body).encode(),
            headers={**self.h, "Prefer": "return=minimal"},
            method="PATCH",
        )
        with urllib.request.urlopen(req, timeout=60) as r:
            r.read()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=500)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--company-id", default=COMPANY)
    args = ap.parse_args()

    url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not url or not key:
        print("Mangler SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY", file=sys.stderr)
        return 2

    sb = Supa(url, key)
    # Mangler FO, sjåfør eller customer_count (encode å i Sjåfør)
    params = urllib.parse.urlencode(
        {
            "company_id": f"eq.{args.company_id}",
            "select": "id,notes,customer_count,pdf_search_text",
            "pdf_search_text": "not.is.null",
            "or": "(notes.not.ilike.*FO:*,notes.not.ilike.*Sjåfør*,customer_count.is.null)",
            "order": "share_date.desc",
            "limit": str(args.limit),
        },
        safe="()*,.:",
    )
    rows = sb.get(f"/rest/v1/partner_route_shares?{params}") or []
    print(f"Kandidater: {len(rows)}")
    updated = 0
    skipped = 0
    for row in rows:
        text = row.get("pdf_search_text") or ""
        if len(text) < 40:
            skipped += 1
            continue
        fo = parse_fo(text)
        driver = parse_driver(text)
        stops = parse_stops(text)
        region, region_n = dominant_region(stops)
        customers = len(stops)
        notes = rebuild_notes(
            row.get("notes"),
            fo=fo,
            driver=driver,
            customers=customers,
            region=region,
            region_n=region_n,
        )
        patch: dict[str, Any] = {"notes": notes}
        if customers > 0:
            patch["customer_count"] = customers
        if args.dry_run:
            print(
                f"  dry {row['id'][:8]} FO={fo} drv={driver} cust={customers} "
                f"area={region}/{region_n}"
            )
            updated += 1
            continue
        try:
            sb.patch(f"/rest/v1/partner_route_shares?id=eq.{row['id']}", patch)
            updated += 1
            if updated % 25 == 0:
                print(f"  …{updated}")
            time.sleep(0.02)
        except Exception as e:
            print(f"  FEIL {row['id']}: {e}", file=sys.stderr)
    print(f"Ferdig. oppdatert={updated} hoppet={skipped}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
