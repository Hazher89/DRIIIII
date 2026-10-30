#!/usr/bin/env python3
"""
Importer Connecteam-PDF-er til DriftPro uten varsel.

- Matcher kun eksisterende MAVI-biler i flåten (oppretter ikke sjåfører/biler)
- Uten match → hopp over
- dispatch_status=sent (synlig i sjåførportal) + notify_channels=[] (ingen push/SMS/e-post)
- ack_status=accepted (ferdig akseptert)

Bruk:
  export SUPABASE_URL='https://….supabase.co'
  export SUPABASE_SERVICE_ROLE_KEY='…'
  python3 scripts/connecteam_import_to_driftpro.py \\
    --in exports/connecteam_pdfs --company-id 00000000-0000-0000-0000-000000000000

Valgfritt:
  --dry-run
  --limit 50
  --from-month 2024-02 --to-month 2026-10
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
import time
import uuid
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    from pypdf import PdfReader
except ImportError:  # pragma: no cover
    PdfReader = None  # type: ignore

MAVI_COMPANY_DEFAULT = "00000000-0000-0000-0000-000000000000"
# DB CHECK: staged_import_source IS NULL OR IN ('manual','sap')
SOURCE_TAG = "manual"
SOURCE_NOTE = "connecteam_archive"
UA = "DriftPro-ConnecteamImport/1.0"


def normalize_mavi(raw: str) -> str:
    s = re.sub(r"\s+", "", (raw or "").strip().upper())
    if not s:
        return ""
    m = re.fullmatch(r"NO_O_M0*(\d{1,5})", s)
    if m:
        return f"NO_O_M{int(m.group(1)):04d}"
    m = re.fullmatch(r"NO_O_M0*([A-Z][A-Z0-9]{1,8})", s)
    if m:
        return f"NO_O_M0{m.group(1)}"
    m = re.fullmatch(r"M0*(\d{1,5})", s)
    if m:
        return f"NO_O_M{int(m.group(1)):04d}"
    m = re.fullmatch(r"M0*([A-Z][A-Z0-9]{1,8})", s)
    if m:
        return f"NO_O_M0{m.group(1)}"
    m = re.fullmatch(r"\d{1,5}", s)
    if m:
        return f"NO_O_M{int(m.group(0)):04d}"
    return s


def match_key(code: str) -> str:
    """NO_O_M0072 / M72 → M72 for oppslag."""
    n = normalize_mavi(code)
    m = re.fullmatch(r"NO_O_M0*(\d{1,5})", n)
    if m:
        return f"M{int(m.group(1))}"
    m = re.fullmatch(r"NO_O_M0*([A-Z][A-Z0-9]{1,8})", n)
    if m:
        return f"M{m.group(1)}"
    m = re.fullmatch(r"M0*(\d{1,5})", n)
    if m:
        return f"M{int(m.group(1))}"
    return n


def extract_mavi_from_filename(name: str) -> str | None:
    base = Path(name).name.strip()
    if not base:
        return None
    upper = (
        base.replace("\uff3f", "_")
        .replace("\u2013", "-")
        .upper()
    )
    for pat in (
        r"NO_O_M0*(\d{1,5})",
        r"[_\-\.]M0*(\d{1,5})(?=[_\-\.]|\.PDF|$)",
        r"^M0*(\d{1,5})(?=[_\-\.]|\.PDF|$)",
        r"(?:^|[_\-\.])M0*(\d{1,5})\.PDF$",
        r"MAVI[_\s-]*(\d{1,5})",
        r"(?:^|[_\-\.\s])M0*(\d{1,5})(?=[_\-\.\s]|\.PDF|$)",
    ):
        m = re.search(pat, upper, re.I)
        if m:
            return normalize_mavi(f"M{int(m.group(1))}")
    for pat in (
        r"NO_O_M0*([A-Z][A-Z0-9]{1,8})",
        r"[_\-\.]M0*([A-Z][A-Z0-9]{1,8})(?=[_\-\.]|\.PDF|$)",
        r"^M0*([A-Z][A-Z0-9]{1,8})(?=[_\-\.]|\.PDF|$)",
    ):
        m = re.search(pat, upper, re.I)
        if m:
            return normalize_mavi(f"M{m.group(1).upper()}")
    return None


def extract_date_from_filename(name: str) -> str | None:
    m = re.search(r"(20\d{2})-(\d{2})-(\d{2})", Path(name).name)
    if not m:
        return None
    return f"{m.group(1)}-{m.group(2)}-{m.group(3)}"


def extract_mavi_from_pdf_text(text: str) -> str | None:
    if not text.strip():
        return None
    header = text[:5000]
    m = re.search(
        r"NO\s*[_\s.-]*O\s*[_\s.-]*M\s*0*(\d{1,5})",
        header,
        re.I,
    )
    if m:
        return normalize_mavi(f"M{int(m.group(1))}")
    m = re.search(r"\bM0*(\d{1,5})\b", header, re.I)
    if m:
        return normalize_mavi(f"M{int(m.group(1))}")
    return None


def extract_driver_from_pdf_text(text: str) -> str | None:
    if not text.strip():
        return None
    m = re.search(
        r"Resource\s*ID\s*(?:\r?\n\s*)?([A-Za-zÆØÅæøå][^\n]+?)\s*\r?\n\s*Driver\s*Name",
        text,
        re.I,
    )
    if m:
        cand = m.group(1).strip()
        if not re.match(r"^(NO_|M\d)", cand, re.I):
            return cand[:80]
    m = re.search(
        r"Driver\s*Name\s*(?:\r?\n\s*)?([A-Za-zÆØÅæøå][^\n]+)",
        text,
        re.I,
    )
    if m:
        line = m.group(1).strip()
        if not line[:1].isdigit() and "KG" not in line:
            return line[:80]
    return None


def pdf_text(path: Path, max_pages: int | None = None) -> str:
    """Extract PDF text. Default = alle sider (trengs for bilag/sales order i søk)."""
    if PdfReader is None:
        return ""
    try:
        reader = PdfReader(str(path))
        pages = reader.pages if max_pages is None else reader.pages[:max_pages]
        parts: list[str] = []
        for page in pages:
            parts.append(page.extract_text() or "")
        return "\n".join(parts)
    except Exception:
        return ""


_VISION_OCR_BIN = Path("/tmp/VisionOCR")


def ocr_pdf_text(path: Path, max_pages: int | None = None) -> str:
    """OCR for vector-tegnet SAP-PDF uten tekstlag (macOS Vision via /tmp/VisionOCR)."""
    try:
        import fitz  # pymupdf
    except ImportError:
        return ""
    if not _VISION_OCR_BIN.is_file():
        return ""
    try:
        doc = fitz.open(str(path))
    except Exception:
        return ""
    parts: list[str] = []
    n = doc.page_count if max_pages is None else min(doc.page_count, max_pages)
    for i in range(n):
        try:
            page = doc.load_page(i)
            pix = page.get_pixmap(matrix=fitz.Matrix(2, 2))
            img = Path(f"/tmp/driftpro_ocr_{os.getpid()}_{i}.png")
            pix.save(str(img))
            import subprocess

            r = subprocess.run(
                [str(_VISION_OCR_BIN), str(img)],
                capture_output=True,
                text=True,
                timeout=90,
            )
            t = (r.stdout or "").strip()
            if t:
                # OCR legger ofte komma foran bilag: ",2120262557"
                t = re.sub(r",(?=\d{7,})", "", t)
                parts.append(t)
            try:
                img.unlink(missing_ok=True)
            except Exception:
                pass
        except Exception:
            continue
    return "\n".join(parts)


def pdf_search_text(path: Path) -> str:
    """Tekst for søk: vanlig ekstraksjon, ellers OCR når PDF er vector uten tekstlag."""
    text = pdf_text(path)
    if len((text or "").strip()) >= 80:
        return text
    ocr = ocr_pdf_text(path)
    if ocr.strip():
        return ocr
    return text or ""


class Supa:
    def __init__(self, url: str, key: str) -> None:
        self.url = url.rstrip("/")
        self.key = key
        self.h = {
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Accept": "application/json",
            "User-Agent": UA,
        }

    def rest(
        self,
        path: str,
        *,
        method: str = "GET",
        body: Any = None,
        extra: dict[str, str] | None = None,
        prefer: str | None = None,
    ) -> Any:
        headers = dict(self.h)
        if prefer:
            headers["Prefer"] = prefer
        if extra:
            headers.update(extra)
        data = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(
            self.url + path, data=data, headers=headers, method=method
        )
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                raw = r.read()
                if not raw:
                    return None
                return json.loads(raw.decode("utf-8"))
        except urllib.error.HTTPError as e:
            err = e.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"HTTP {e.code} {method} {path}: {err[:500]}") from e

    def upload(self, bucket: str, storage_path: str, raw: bytes) -> None:
        headers = dict(self.h)
        headers["Content-Type"] = "application/pdf"
        headers["x-upsert"] = "true"
        enc = "/".join(urllib.parse.quote(p, safe="") for p in storage_path.split("/"))
        req = urllib.request.Request(
            f"{self.url}/storage/v1/object/{bucket}/{enc}",
            data=raw,
            headers=headers,
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                r.read()
        except urllib.error.HTTPError as e:
            # upsert via PUT if POST fails (exists)
            if e.code in (400, 409):
                req2 = urllib.request.Request(
                    f"{self.url}/storage/v1/object/{bucket}/{enc}",
                    data=raw,
                    headers=headers,
                    method="PUT",
                )
                with urllib.request.urlopen(req2, timeout=180) as r:
                    r.read()
                return
            err = e.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"upload HTTP {e.code}: {err[:400]}") from e


def load_fleet(
    sb: Supa,
    company_id: str,
    *,
    include_inactive: bool = False,
) -> dict[str, dict[str, Any]]:
    """match_key → vehicle row (prefer active)."""
    partners = sb.rest(
        f"/rest/v1/partners?company_id=eq.{company_id}&select=id,name,is_active&limit=500"
    ) or []
    partner_ok = {p["id"] for p in partners if p.get("is_active", True)}
    # Hent kjøretøy via partner_ids (unngår PostgREST embed-quirk).
    partner_ids = list(partner_ok)
    vehs: list[dict[str, Any]] = []
    for i in range(0, len(partner_ids), 80):
        chunk = partner_ids[i : i + 80]
        in_list = ",".join(chunk)
        batch = sb.rest(
            "/rest/v1/partner_vehicles"
            "?select=id,unit_code,driver_name,partner_id,is_active"
            f"&partner_id=in.({in_list})&limit=1000"
        ) or []
        vehs.extend(batch)
    by_key: dict[str, dict[str, Any]] = {}
    for v in vehs:
        if v.get("partner_id") not in partner_ok:
            continue
        if not include_inactive and not v.get("is_active", True):
            continue
        code = v.get("unit_code") or ""
        if code.upper().startswith("REG-"):
            continue
        key = match_key(code)
        if not key.startswith("M"):
            continue
        cur = by_key.get(key)
        if cur is None:
            by_key[key] = v
            continue
        # Prefer active, then one with driver_name
        score = (1 if v.get("is_active") else 0) + (1 if v.get("driver_name") else 0)
        cur_score = (1 if cur.get("is_active") else 0) + (
            1 if cur.get("driver_name") else 0
        )
        if score > cur_score:
            by_key[key] = v
    return by_key


def load_existing_sources(sb: Supa, company_id: str) -> set[str]:
    """Find notes markers Connecteam-source:… already imported."""
    out: set[str] = set()
    offset = 0
    while True:
        rows = sb.rest(
            f"/rest/v1/partner_route_shares?company_id=eq.{company_id}"
            f"&select=notes&notes=like.*Connecteam-source:*"
            f"&limit=1000&offset={offset}"
        ) or []
        if not rows:
            break
        for row in rows:
            notes = row.get("notes") or ""
            m = re.search(r"Connecteam-source:\s*(\S+)", notes)
            if m:
                out.add(m.group(1).strip())
        if len(rows) < 1000:
            break
        offset += len(rows)
    return out


def iter_pdfs(root: Path, from_m: str | None, to_m: str | None) -> list[Path]:
    files: list[Path] = []
    seen: set[Path] = set()
    for pattern in ("*.pdf", "*.PDF"):
        for p in root.rglob(pattern):
            if p in seen or p.name.endswith(".part"):
                continue
            seen.add(p)
            month = None
            for part in p.parts:
                if re.fullmatch(r"20\d{2}-\d{2}", part):
                    month = part
                    break
            if from_m and month and month < from_m:
                continue
            if to_m and month and month > to_m:
                continue
            files.append(p)
    return sorted(files)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="indir", default="exports/connecteam_pdfs")
    ap.add_argument("--company-id", default=MAVI_COMPANY_DEFAULT)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--from-month", default=None)
    ap.add_argument("--to-month", default=None)
    ap.add_argument("--sleep", type=float, default=0.03)
    ap.add_argument(
        "--archive-missing",
        action="store_true",
        help="Importer også til inaktive Connecteam-arkiv-MAVI (historikk/søk).",
    )
    ap.add_argument(
        "--only",
        default=None,
        help="Kun filer som inneholder denne delstrengen i relativ sti/filnavn.",
    )
    args = ap.parse_args()

    url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not url or not key:
        print(
            "Sett SUPABASE_URL og SUPABASE_SERVICE_ROLE_KEY i miljøet.",
            file=sys.stderr,
        )
        return 2

    root = Path(args.indir)
    if not root.is_dir():
        print(f"Fant ikke mappe: {root}", file=sys.stderr)
        return 1

    sb = Supa(url, key)
    print("Laster flåte…")
    fleet = load_fleet(
        sb,
        args.company_id,
        include_inactive=bool(args.archive_missing),
    )
    active_n = sum(1 for v in fleet.values() if v.get("is_active", True))
    print(
        f"  MAVI-biler i DriftPro: {len(fleet)}"
        f" (aktive={active_n}"
        f"{', inkl. arkiv' if args.archive_missing else ''})"
    )
    print("Laster allerede importerte Connecteam-kilder…")
    existing = load_existing_sources(sb, args.company_id)
    print(f"  allerede importert: {len(existing)}")

    files = iter_pdfs(root, args.from_month, args.to_month)
    if args.only:
        needle = args.only.strip().lower()
        files = [
            p
            for p in files
            if needle in str(p.relative_to(root)).replace("\\", "/").lower()
            or needle in p.name.lower()
        ]
    if args.limit > 0:
        files = files[: args.limit]
    print(f"PDF-filer å vurdere: {len(files)}")

    log_path = root / "import_log.csv"
    write_header = not log_path.exists()
    stats = {
        "imported": 0,
        "skipped_no_vehicle": 0,
        "skipped_exists": 0,
        "skipped_bad": 0,
        "errors": 0,
    }

    with open(log_path, "a", newline="", encoding="utf-8") as lf:
        w = csv.DictWriter(
            lf,
            fieldnames=[
                "rel_path",
                "mavi",
                "vehicle_id",
                "share_date",
                "status",
                "share_id",
                "detail",
            ],
        )
        if write_header:
            w.writeheader()

        for i, path in enumerate(files, 1):
            rel = str(path.relative_to(root)).replace("\\", "/")
            source_key = rel
            if source_key in existing:
                stats["skipped_exists"] += 1
                # Ikke logg hvert hopp — holder CSV liten og unngår at jobben ser «død» ut.
                if i % 500 == 0:
                    print(
                        f"  …{i}/{len(files)}  "
                        f"ok={stats['imported']} skip_veh={stats['skipped_no_vehicle']} "
                        f"exists={stats['skipped_exists']} err={stats['errors']}"
                    )
                    lf.flush()
                continue

            if path.stat().st_size < 200:
                stats["skipped_bad"] += 1
                w.writerow(
                    {
                        "rel_path": rel,
                        "mavi": "",
                        "vehicle_id": "",
                        "share_date": "",
                        "status": "skipped_bad",
                        "share_id": "",
                        "detail": "for liten fil",
                    }
                )
                continue

            text = ""
            mavi = extract_mavi_from_filename(path.name)
            if not mavi:
                text = pdf_text(path)
                mavi = extract_mavi_from_pdf_text(text)

            if not mavi:
                stats["skipped_no_vehicle"] += 1
                w.writerow(
                    {
                        "rel_path": rel,
                        "mavi": "",
                        "vehicle_id": "",
                        "share_date": "",
                        "status": "skipped_no_mavi",
                        "share_id": "",
                        "detail": "fant ikke MAVI",
                    }
                )
                continue

            veh = fleet.get(match_key(mavi))
            if not veh:
                stats["skipped_no_vehicle"] += 1
                w.writerow(
                    {
                        "rel_path": rel,
                        "mavi": mavi,
                        "vehicle_id": "",
                        "share_date": "",
                        "status": "skipped_no_vehicle",
                        "share_id": "",
                        "detail": "ikke i DriftPro-flåte",
                    }
                )
                continue
            if not veh.get("is_active", True) and not args.archive_missing:
                # Kun aktive biler som finnes i DriftPro nå — ingen nye sjåfører.
                stats["skipped_no_vehicle"] += 1
                w.writerow(
                    {
                        "rel_path": rel,
                        "mavi": mavi,
                        "vehicle_id": "",
                        "share_date": "",
                        "status": "skipped_no_vehicle",
                        "share_id": "",
                        "detail": "ikke i DriftPro-flåte (aktiv)",
                    }
                )
                continue

            share_date = extract_date_from_filename(path.name)
            if not share_date:
                stats["skipped_bad"] += 1
                w.writerow(
                    {
                        "rel_path": rel,
                        "mavi": mavi,
                        "vehicle_id": veh["id"],
                        "share_date": "",
                        "status": "skipped_no_date",
                        "share_id": "",
                        "detail": "mangler dato i filnavn",
                    }
                )
                continue

            # Full tekst for søk (bilag/sales order ligger ofte på side 2+).
            # SAP Trip Overview er ofte vector uten tekstlag → OCR-fallback.
            header = text or pdf_text(path, max_pages=1)
            text = pdf_search_text(path)
            if not text:
                text = header
            if text and len(text.strip()) >= 80 and len((header or "").strip()) < 40:
                print(f"  OCR: {rel} ({len(text)} tegn)")
            driver = extract_driver_from_pdf_text(header or text) or veh.get(
                "driver_name"
            )
            fo = None
            fo_src = header or text
            if fo_src:
                mfo = re.search(
                    r"Freight\s*Order\s*[:#]?\s*(\d{6,14})", fo_src, re.I
                )
                if not mfo:
                    # OCR: "Freight Order" på egen linje, tallet under
                    mfo = re.search(
                        r"Freight\s*Order\s*\n\s*(\d{6,14})", fo_src, re.I
                    )
                if not mfo:
                    mfo = re.search(r"\b(610\d{7})\b", fo_src)
                if mfo:
                    fo = mfo.group(1)
            # Områdehint fra Connecteam-filnavn: «Kveldsrute_-_Østfold_…»
            area_hint = None
            for label in (
                "Østfold",
                "Ostfold",
                "Bærum",
                "Baerum",
                "Jessheim",
                "Drammen",
                "Nesodden",
                "Nittedal",
                "Hønefoss",
                "Honefoss",
                "Kongsvinger",
                "Oslo",
                "Ski",
                "Indre",
            ):
                if label.lower() in path.name.lower().replace("ø", "o").replace(
                    "æ", "ae"
                ) or label.lower() in path.name.lower():
                    area_hint = (
                        "Østfold"
                        if label.lower() in ("ostfold", "østfold")
                        else "Bærum"
                        if label.lower() in ("baerum", "bærum")
                        else "Hønefoss"
                        if label.lower() in ("honefoss", "hønefoss")
                        else label
                    )
                    break
            notes_parts = [
                f"Connecteam-source: {source_key}",
                f"Import: {SOURCE_NOTE}",
            ]
            if not veh.get("is_active", True):
                notes_parts.append(
                    "Arkiv: historisk MAVI (ikke aktiv i dagens flåte)"
                )
            if fo:
                notes_parts.append(f"FO: {fo}")
            if driver:
                notes_parts.append(f"Sjåfør (PDF): {driver}")
            if area_hint:
                notes_parts.append(f"Område: {area_hint}")
            notes = "\n".join(notes_parts)

            title = f"Rute {match_key(mavi)} — {path.name}"
            now = datetime.now(timezone.utc).isoformat()
            safe_file = re.sub(r"[^A-Za-z0-9._-]+", "_", path.name)[:120]
            if not safe_file.lower().endswith(".pdf"):
                safe_file += ".pdf"
            storage_path = (
                f"company_{args.company_id}/partner_routes/"
                f"{int(time.time() * 1000)}_{normalize_mavi(mavi)}_"
                f"{uuid.uuid4().hex[:8]}_{safe_file}"
            )

            if args.dry_run:
                stats["imported"] += 1
                w.writerow(
                    {
                        "rel_path": rel,
                        "mavi": mavi,
                        "vehicle_id": veh["id"],
                        "share_date": share_date,
                        "status": "dry_run",
                        "share_id": "",
                        "detail": storage_path,
                    }
                )
            else:
                try:
                    raw = path.read_bytes()
                    sb.upload("documents", storage_path, raw)
                    row = {
                        "partner_id": veh["partner_id"],
                        "company_id": args.company_id,
                        "partner_vehicle_id": veh["id"],
                        "title": title[:240],
                        "pdf_storage_path": storage_path,
                        "share_date": share_date,
                        "is_daily_share": True,
                        "dispatch_status": "sent",
                        "notify_channels": [],
                        "ack_status": "accepted",
                        "ack_at": now,
                        "ack_comment": "Connecteam-arkiv: auto-akseptert uten varsel",
                        "sent_at": now,
                        "notes": notes,
                        "staged_import_source": SOURCE_TAG,
                        "pdf_search_text": (text[:50000] if text else None),
                    }
                    inserted = sb.rest(
                        "/rest/v1/partner_route_shares",
                        method="POST",
                        body=row,
                        prefer="return=representation",
                    )
                    share_id = ""
                    if isinstance(inserted, list) and inserted:
                        share_id = str(inserted[0].get("id") or "")
                    stats["imported"] += 1
                    existing.add(source_key)
                    w.writerow(
                        {
                            "rel_path": rel,
                            "mavi": mavi,
                            "vehicle_id": veh["id"],
                            "share_date": share_date,
                            "status": "imported",
                            "share_id": share_id,
                            "detail": "",
                        }
                    )
                    time.sleep(args.sleep)
                except Exception as e:
                    stats["errors"] += 1
                    w.writerow(
                        {
                            "rel_path": rel,
                            "mavi": mavi,
                            "vehicle_id": veh["id"],
                            "share_date": share_date,
                            "status": "error",
                            "share_id": "",
                            "detail": str(e)[:300],
                        }
                    )
                    print(f"  FEIL {rel}: {e}", file=sys.stderr)

            if i % 50 == 0:
                lf.flush()
                print(
                    f"  …{i}/{len(files)}  "
                    f"ok={stats['imported']} skip_veh={stats['skipped_no_vehicle']} "
                    f"exists={stats['skipped_exists']} err={stats['errors']}"
                )

    print("\nFerdig import:")
    for k, v in stats.items():
        print(f"  {k}: {v}")
    print(f"Logg: {log_path}")
    return 0 if stats["errors"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
