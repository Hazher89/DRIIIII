# DriftPro Ruteplan — Last-Mile Logistics (Elkjøp)

## Mål

**Erstatte SAP (ordre/rute-PDF) og TransFleet (planlegging, dispatch, sporing)** med ett eget økosystem:

| Komponent | Rolle | Erstatter |
|-----------|--------|-----------|
| **DriftPro Ruteplan** (Mac/PC) | Master route planner, VRPTW, kart-dispatch | TransFleet + SAP planlegging |
| **Sjåfør-app** (iOS/Android) | Lager, levering, GPS, PoD | TransFleet mobil + papir |
| **Supabase** | Operativ hub (ordre, ruter, GPS, PoD) | SAP/TransFleet databaser |
| **DriftPro (driftpro.no)** | **Master** for flåte, sjåfør, kapasitet, bedrifter | — |

**DriftPro er ikke en kopi av ERP i desktop** — desktop er et dedikert logistikkprodukt som **leser masterdata fra DriftPro** og **skriver operativ data tilbake** til Supabase.

---

## Arkitektur

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  driftpro.no    │     │    Supabase      │     │ DriftPro Ruteplan│
│  (master)       │────▶│  PostgreSQL      │◀────│  Mac / Windows   │
│  flåte, sjåfør  │     │  Realtime        │     │  VRPTW + kart    │
│  payload, RLS   │     │  Storage         │     └─────────────────┘
└─────────────────┘     │        ▲         │     ┌─────────────────┐
                        │        │         │────▶│  Sjåfør-app      │
                        │  lm_* tabeller   │     │  GPS, PoD, scan  │
                        └──────────────────┘     └─────────────────┘
                                    │
                        ┌───────────┴───────────┐
                        │  Offentlig sporings-URL │
                        └───────────────────────┘
```

---

## Datamodell (nytt — `lm_*`)

| Tabell | Formål |
|--------|--------|
| `lm_orders` | Kundeordre (adresse, vindu, vekt/volum, Elkjøp-linjer) |
| `lm_routes` | Planlagt rute per MAVI-bil / dag |
| `lm_route_stops` | Stopp i rekkefølge (koblet til ordre) |
| `lm_route_custom_field_defs` | Dynamiske felt per rute (montering, bærebelte, …) |
| `lm_optimization_runs` | VRPTW-kjøringer og resultat |
| `lm_gps_positions` | Live posisjon fra sjåfør-app |
| `lm_pod_records` | Signatur, foto, geotag |
| `lm_tracking_sessions` | Token for kunde-sporing |
| `lm_warehouse_items` | Framplukk / mottak (strekkode) |
| `lm_fleet_sync_runs` | Logg: sist synket fra DriftPro |

**Kobling til DriftPro:** `company_id`, `partner_id`, `partner_vehicle_id`, `shift_id`, `driver_profile_id` — ingen duplikat flåte-register.

---

## Funksjoner vs. status

### 1. Desktop — Master Route Planner

| Funksjon | Status |
|----------|--------|
| Installérbar Mac/PC | ✅ `main_dispatch.dart` |
| Sync flåte/sjåfør/kapasitet fra DriftPro | ✅ `DriftproFleetSyncService` |
| Ordrekø (erstatter SAP-innboks) | ✅ `lm_orders` + UI + PDF/SAP import |
| VRPTW optimalisering | ✅ `VrptwOptimizer` + persist ruter |
| Kart + drag-drop dispatch | ✅ `flutter_map` + ReorderableListView |
| Dynamiske egendefinerte felt | ✅ Schema + seed migrasjon |
| PDF-import (overgang fra SAP) | ✅ Bro til `lm_orders` |

### 2. Sjåfør-app

| Funksjon | Status |
|----------|--------|
| Innlogging (Supabase / DriftPro) | ✅ `main_driver.dart` |
| Rute-liste + navigasjon | ✅ Google Maps lenke |
| Strekkode mottak | ✅ `mobile_scanner` + `lm_warehouse_items` |
| GPS bakgrunn → Realtime | ✅ `LmGpsService` hvert 30s |
| PoD (signatur, foto) | ✅ `signature` + `lm_pod_records` |

### 3. Track & Trace

| Funksjon | Status |
|----------|--------|
| Live kart på desktop | ✅ Realtime + `flutter_map` |
| Offentlig sporings-URL | ✅ `?track=token` + `lm_public_tracking` RPC |

---

## Faser (anbefalt)

1. **Fase 1 — Fundament** (nå): Schema `lm_*`, fleet sync, desktop shell med moduler, ordrekø.
2. **Fase 2 — Planlegger**: VRPTW, kart, manuell drag-drop, publisering til sjåfør.
3. **Fase 3 — Sjåfør-app**: Flutter mobil, GPS, PoD, lager.
4. **Fase 4 — Sporing**: Realtime kart, kunde-URL, avvikde SAP/TransFleet.

---

## Entry points

| App | Fil |
|-----|-----|
| ERP web/mobil | `lib/main.dart` |
| **Ruteplan Mac/PC** | `lib/main_dispatch.dart` |

Bygg: `./tools/build_desktop.sh macos`
