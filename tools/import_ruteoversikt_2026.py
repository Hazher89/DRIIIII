#!/usr/bin/env python3
"""Genererer Supabase-migrasjon fra «Ruteoversikt 2026.xlsx»."""

from __future__ import annotations

import re
import zipfile
import xml.etree.ElementTree as ET
from collections import Counter
from datetime import datetime, timedelta
from pathlib import Path

EXCEL_PATH = Path('/Users/hama/MAVI PRO/Ruteoversikt 2026.xlsx')
OUT_SQL = Path(__file__).resolve().parents[1] / 'supabase/migrations/20260604140000_seed_ruteoversikt_2026.sql'

NS = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
MAVI_RE = re.compile(r'^M\s*0*(\d{1,3})\b', re.I)
SHIFT_CELL_RE = re.compile(r'^([DK])\s*-\s*(.+)$', re.I)

REGION_ALIASES = {
    'oslo': 'Oslo',
    'baerum': 'Bærum',
    'bærum': 'Bærum',
    'drammen': 'Drammen',
    'hønefoss': 'Hønefoss',
    'honefoss': 'Hønefoss',
    'jessheim': 'Jessheim',
    'nittedal': 'Nittedal',
    'nesodden': 'Nesodden',
    'ski': 'Ski',
    'indre': 'Indre',
    'østfold': 'Østfold',
    'ostfold': 'Østfold',
    'kongsvinger': 'Kongsvinger',
}

AVAILABILITY_LABELS = {
    'fri': 'Fri',
    'syk': 'Syk',
    'gitt bort': 'Gitt bort',
    'ledig': 'LEDIG HELE DAG',
}


def norm_key(s: str) -> str:
    return s.lower().replace('æ', 'ae').replace('ø', 'o').replace('å', 'aa').strip()


def map_shift_label(label: str) -> str | None:
    raw = label.strip()
    if not raw:
        return None
    key = norm_key(raw)
    if key in AVAILABILITY_LABELS:
        return AVAILABILITY_LABELS[key]
    if key in ('intern', 'kun kveld', 'kun dag'):
        return None
    if key == 'dobbel':
        return 'Dagrute - Oslo'
    if key == 'geilo':
        return 'Dagrute - Hønefoss'

    m = SHIFT_CELL_RE.match(raw)
    if not m:
        return None
    band = 'Dagrute' if m.group(1).upper() == 'D' else 'Kveldsrute'
    region_raw = m.group(2).strip()
    region = REGION_ALIASES.get(norm_key(region_raw), region_raw)
    return f'{band} - {region}'


def mavi_unit_code(label: str) -> str | None:
    m = MAVI_RE.match(label.strip())
    if not m:
        return None
    n = int(m.group(1))
    return f'NO_O_M{n:04d}'


def read_workbook(path: Path):
    z = zipfile.ZipFile(path)
    ss: list[str] = []
    if 'xl/sharedStrings.xml' in z.namelist():
        root = ET.fromstring(z.read('xl/sharedStrings.xml'))
        for si in root.findall('.//m:si', NS):
            ss.append(''.join((t.text or '') for t in si.findall('.//m:t', NS)))

    rels = ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))
    rns = {'r': 'http://schemas.openxmlformats.org/package/2006/relationships'}
    id_to_target = {
        rel.get('Id'): 'xl/' + rel.get('Target').replace('../', '')
        for rel in rels.findall('r:Relationship', rns)
    }

    wb = ET.fromstring(z.read('xl/workbook.xml'))
    sheets = []
    for sh in wb.findall('.//m:sheet', NS):
        name = sh.get('name') or ''
        rid = sh.get('{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id')
        target = id_to_target.get(rid)
        if not target or not name.startswith('UKE'):
            continue
        root = ET.fromstring(z.read(target))
        rows: dict[int, dict[str, str]] = {}
        for row in root.findall('.//m:sheetData/m:row', NS):
            rnum = int(row.get('r', 0))
            cells: dict[str, str] = {}
            for c in row.findall('m:c', NS):
                ref = c.get('r', '')
                col = ''.join(ch for ch in ref if ch.isalpha())
                t = c.get('t')
                v = c.find('m:v', NS)
                val = v.text if v is not None else ''
                if t == 's' and val.isdigit():
                    val = ss[int(val)] if int(val) < len(ss) else val
                cells[col] = str(val).strip()
            if cells:
                rows[rnum] = cells
        sheets.append((name, rows))
    return sheets


def parse_sheet(rows: dict[int, dict[str, str]]):
    date_row = rows.get(3, {})
    cols_dates: list[tuple[str, str]] = []
    for col, val in date_row.items():
        if not val.replace('.', '').isdigit():
            continue
        serial = int(float(val))
        if serial < 40000:
            continue
        d = datetime(1899, 12, 30) + timedelta(days=serial)
        cols_dates.append((col, d.date().isoformat()))

    records = []
    for rnum, cells in rows.items():
        if rnum < 4:
            continue
        label = cells.get('A', '')
        unit = mavi_unit_code(label)
        if unit is None:
            continue
        comment = cells.get('B', '').strip()
        for col, day in cols_dates:
            cell = cells.get(col, '').strip()
            if not cell:
                continue
            shift_name = map_shift_label(cell)
            if shift_name is None:
                continue
            note = cell if cell != shift_name else None
            if comment:
                note = f'{comment}' + (f' · {note}' if note else '')
            records.append((unit, day, shift_name, note))
    return records


def sql_escape(s: str | None) -> str:
    if s is None:
        return 'NULL'
    return "'" + s.replace("'", "''") + "'"


def main():
    if not EXCEL_PATH.exists():
        raise SystemExit(f'Mangler fil: {EXCEL_PATH}')

    deduped: dict[tuple[str, str], tuple[str, str, str, str | None]] = {}
    for name, rows in read_workbook(EXCEL_PATH):
        recs = parse_sheet(rows)
        for rec in recs:
            deduped[(rec[0], rec[1])] = rec
        print(f'{name}: {len(recs)} celler')

    all_records = list(deduped.values())
    print(f'Totalt etter deduplisering: {len(all_records)} celler')

    lines = [
        '-- Seed fra Ruteoversikt 2026.xlsx (generert av tools/import_ruteoversikt_2026.py)',
        '-- Krever: 20260604120000_mavi_driver_day_assignments.sql',
        '',
        'CREATE TEMP TABLE IF NOT EXISTS _ruteoversikt_import (',
        '  unit_code TEXT NOT NULL,',
        '  assignment_date DATE NOT NULL,',
        '  shift_name TEXT NOT NULL,',
        '  notes TEXT',
        ') ON COMMIT DROP;',
        'TRUNCATE _ruteoversikt_import;',
        '',
    ]

    batch_size = 400
    for i in range(0, len(all_records), batch_size):
        chunk = all_records[i : i + batch_size]
        lines.append('INSERT INTO _ruteoversikt_import (unit_code, assignment_date, shift_name, notes) VALUES')
        value_lines = []
        for unit, day, shift, note in chunk:
            value_lines.append(
                f"  ({sql_escape(unit)}, {sql_escape(day)}, {sql_escape(shift)}, {sql_escape(note)})"
            )
        lines.append(',\n'.join(value_lines) + ';')
        lines.append('')

    lines.extend(
        [
            'INSERT INTO public.mavi_driver_day_assignments (',
            '  company_id, partner_vehicle_id, assignment_date, shift_id, notes, updated_at',
            ')',
            'SELECT DISTINCT ON (pv.id, i.assignment_date)',
            '  pv.company_id,',
            '  pv.id,',
            '  i.assignment_date,',
            '  fs.id,',
            '  i.notes,',
            '  now()',
            'FROM _ruteoversikt_import i',
            'JOIN LATERAL (',
            '  SELECT id, company_id',
            '  FROM public.partner_vehicles',
            '  WHERE upper(unit_code) = upper(i.unit_code)',
            '  ORDER BY is_active DESC, created_at DESC',
            '  LIMIT 1',
            ') pv ON true',
            'JOIN LATERAL (',
            '  SELECT id',
            '  FROM public.fleet_shift_definitions',
            '  WHERE company_id = pv.company_id',
            '    AND name = i.shift_name',
            '    AND NOT is_archived',
            '  ORDER BY sort_order',
            '  LIMIT 1',
            ') fs ON true',
            'ORDER BY pv.id, i.assignment_date',
            'ON CONFLICT (partner_vehicle_id, assignment_date) DO UPDATE SET',
            '  shift_id = EXCLUDED.shift_id,',
            '  notes = EXCLUDED.notes,',
            '  updated_at = now();',
            '',
            '-- Flåte-snapshot (samme skift, status avledet fra skifttype)',
            'INSERT INTO public.partner_vehicle_fleet_snapshots (',
            '  company_id, partner_vehicle_id, snapshot_date, shift_id, status, notes, updated_at',
            ')',
            'SELECT',
            '  a.company_id,',
            '  a.partner_vehicle_id,',
            '  a.assignment_date,',
            '  a.shift_id,',
            '  CASE',
            "    WHEN fs.shift_kind = 'availability' AND fs.name ILIKE '%fri%' AND fs.name NOT ILIKE '%ledig%' THEN 'fri'",
            "    WHEN fs.shift_kind = 'availability' AND fs.name ILIKE '%gitt%' THEN 'gitt_bort'",
            "    ELSE 'ledig'",
            '  END,',
            "  coalesce(a.notes, 'Ruteoversikt 2026'),",
            '  now()',
            'FROM public.mavi_driver_day_assignments a',
            'JOIN public.fleet_shift_definitions fs ON fs.id = a.shift_id',
            'JOIN _ruteoversikt_import i',
            '  ON i.assignment_date = a.assignment_date',
            'JOIN public.partner_vehicles pv ON pv.id = a.partner_vehicle_id AND upper(pv.unit_code) = upper(i.unit_code)',
            'ON CONFLICT (partner_vehicle_id, snapshot_date, shift_id) DO UPDATE SET',
            '  status = EXCLUDED.status,',
            '  notes = EXCLUDED.notes,',
            '  updated_at = now();',
        ]
    )

    OUT_SQL.write_text('\n'.join(lines), encoding='utf-8')
    print(f'Skrev: {OUT_SQL} ({OUT_SQL.stat().st_size // 1024} KB)')


if __name__ == '__main__':
    main()
