# URL-ruting i DriftPro (web)

DriftPro bruker **go_router** med **path-URL** (ikke `#/dashboard`). Refresh og bokmerker skal fungere for hovedfaner.

## Hovedfaner (bottom nav)

| Side | URL |
|------|-----|
| Dashboard | `/` |
| Undersøkelser | `/surveys` |
| Fravær | `/fravaer` |
| Avvik | `/avvik` |
| HMS | `/hms` |
| Partnere / ruter | `/partners` |
| Mer | `/more` |

## Offentlige / spesielle

| Side | URL |
|------|-----|
| Innlogging | `/login` |
| Undersøkelse (delt) | `/s/{id}` eller `?survey=` |
| Kundesporing | `/track/{token}` eller `?track=` |
| Infoskjerm | `/live` eller `?view=infoskjerm` |

## Programmatisk navigasjon

```dart
import 'package:go_router/go_router.dart';
import 'package:driftpro/core/routing/app_paths.dart';

context.go(AppPaths.partners);
context.go(AppPaths.pathForAccess(AccessKeys.avvik)!);
```

## Neste steg (ikke ferdig ennå)

Undersider åpnet med `Navigator.push` (Mer-meny, HMS-undermoduler, partner-detalj, dialoger) har **egen URL ikke ennå**. Mønster for utvidelse:

- `/more/ansatte`, `/more/tilgangskontroll`, …
- `/hms/utstyr`, `/hms/sja`, …
- `/partners/{partnerId}/ruter`

Disse legges gradvis til som `GoRoute` under riktig gren.
