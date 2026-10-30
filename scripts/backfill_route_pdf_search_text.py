#!/usr/bin/env python3
"""Re-indekser pdf_search_text fra Connecteam-PDF (alle sider) for bilag-søk.

Bruk:
  SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \\
    python3 scripts/backfill_route_pdf_search_text.py \\
      --in exports/connecteam_pdfs --from-month 2025-01 --to-month 2025-12
"""
from __future__ import annotations

import argparse
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

try:
    from pypdf import PdfReader
except ImportError:
    try:
        from PyPDF2 import PdfReader  # type: ignore
    except ImportError:
        PdfReader = None  # type: ignore

UA = "driftpro-backfill-pdf-search/1.0"


def pdf_full_text(path: Path) -> str:
    if PdfReader is None:
        return ""
    try:
        reader = PdfReader(str(path))
        return "\n".join((p.extract_text() or "") for p in reader.pages)
    except Exception:
        return ""


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
        data = None
        if body is not None:
            import json

            data = json.dumps(body).encode()
        req = urllib.request.Request(
            self.url + path, data=data, headers=headers, method=method
        )
        import json
        import time as _time
        last_err = None
        for attempt in range(5):
            try:
                with urllib.request.urlopen(req, timeout=180) as r:
                    raw = r.read().decode()
                    if not raw:
                        return None
                    return json.loads(raw)
            except Exception as e:
                last_err = e
                _time.sleep(1.5 * (attempt + 1))
        raise last_err  # type: ignore



def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="indir", default="exports/connecteam_pdfs")
    ap.add_argument("--from-month", default="2025-01")
    ap.add_argument("--to-month", default="2025-12")
    ap.add_argument("--company-id", default="00000000-0000-0000-0000-000000000000")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--sleep", type=float, default=0.05)
    args = ap.parse_args()

    url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not url or not key:
        print("Sett SUPABASE_URL og SUPABASE_SERVICE_ROLE_KEY", file=sys.stderr)
        return 2
    if PdfReader is None:
        print("Mangler pypdf/PyPDF2", file=sys.stderr)
        return 2

    root = Path(args.indir)
    sb = Supa(url, key)

    def month_start(ym: str) -> str:
        return f"{ym}-01"

    def month_end(ym: str) -> str:
        y, m = map(int, ym.split("-"))
        if m == 12:
            return f"{y}-12-31"
        import datetime as _dt

        return (_dt.date(y, m + 1, 1) - _dt.timedelta(days=1)).isoformat()

    # Hent Connecteam-shares i perioden (paginert)
    shares: list[dict] = []
    offset = 0
    d_from = month_start(args.from_month)
    d_to = month_end(args.to_month)
    while True:
        rows = (
            sb.rest(
                f"/rest/v1/partner_route_shares?company_id=eq.{args.company_id}"
                f"&select=id,notes,pdf_search_text,share_date"
                f"&notes=like.*Connecteam-source:*"
                f"&share_date=gte.{d_from}"
                f"&share_date=lte.{d_to}"
                f"&order=share_date.asc&limit=500&offset={offset}"
            )
            or []
        )
        if not rows:
            break
        shares.extend(rows)
        if len(rows) < 500:
            break
        offset += len(rows)
        if args.limit and len(shares) >= args.limit:
            shares = shares[: args.limit]
            break

    print(f"Shares å vurdere: {len(shares)}")
    updated = 0
    skipped = 0
    missing = 0
    errors = 0

    for i, row in enumerate(shares, 1):
        notes = row.get("notes") or ""
        m = re.search(r"Connecteam-source:\s*(\S+)", notes)
        if not m:
            skipped += 1
            continue
        rel = m.group(1).strip()
        path = root / rel
        if not path.is_file():
            # prøv case variants
            alt = list(root.glob(rel))
            if not alt:
                missing += 1
                continue
            path = alt[0]

        text = pdf_full_text(path)
        if not text.strip():
            skipped += 1
            continue
        trimmed = text[:50000]
        old = row.get("pdf_search_text") or ""
        # Hopp hvis allerede har bilag-lignende tall og er lengre enn header-only
        if len(old) > 4000 and re.search(r"\b2\d{9}\b", old):
            skipped += 1
            continue
        if old == trimmed:
            skipped += 1
            continue
        try:
            sb.rest(
                f"/rest/v1/partner_route_shares?id=eq.{row['id']}",
                method="PATCH",
                body={"pdf_search_text": trimmed},
                prefer="return=minimal",
            )
            updated += 1
        except urllib.error.HTTPError as e:
            errors += 1
            print(f"  FEIL {rel}: {e}", file=sys.stderr)
        if i % 25 == 0:
            print(
                f"  …{i}/{len(shares)}  updated={updated} skip={skipped} "
                f"missing={missing} err={errors}"
            )
        time.sleep(args.sleep)

    print(
        f"\nFerdig backfill: updated={updated} skip={skipped} "
        f"missing={missing} err={errors}"
    )
    return 0 if errors == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
