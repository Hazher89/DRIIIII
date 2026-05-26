# DriftPro Ruteplan — Mac & PC

**Egen installérbar last-mile app** som skal **erstatte SAP og TransFleet** for Elkjøp hjemlevering.

Les full produktspesifikasjon: [LAST_MILE_PRODUCT.md](./LAST_MILE_PRODUCT.md)

## Hva det er (og ikke er)

| | DriftPro Ruteplan | driftpro.no |
|---|---|---|
| Formål | Ordre, VRPTW, kart-dispatch, GPS, PoD | ERP master (flåte, sjåfør, HMS, …) |
| Erstatter | SAP + TransFleet | — |
| Data | Supabase `lm_*` + lesing fra DriftPro | Master register |

## Kjøre

```bash
# Desktop planlegger (Mac/PC)
flutter run -d macos -t lib/main_dispatch.dart
./tools/build_desktop.sh macos

# Sjåfør-app (iOS/Android)
flutter run -t lib/main_driver.dart

# Kundesporing (web ERP)
# https://din-app/?track=PUBLIC_TOKEN
```

## Database

Kjør begge migrasjoner i Supabase SQL Editor (eller `supabase db push`):

1. `supabase/migrations/20260524120000_last_mile_logistics_core.sql`
2. `supabase/migrations/20260524130000_last_mile_public_tracking_rpc.sql`

## Moduler i desktop (nå)

1. **Oversikt** — sync status DriftPro flåte
2. **Ordre** — `lm_orders` (SAP-erstatning)
3. **Planlegger** — VRPTW, kart, drag-drop, publiser + `?track=token`
4. **PDF-import** — midlertidig SAP-PDF bro
5. **Sporing** — live GPS-kart (Realtime)
6. **Skift** — skiftplan fra DriftPro
