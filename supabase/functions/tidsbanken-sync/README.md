# Tidsbanken sync (web-innlogging)

Henter live «hvem er på jobb» fra Tidsbanken uten API-nøkkel.

## Supabase Secrets (Project → Edge Functions → Secrets)

| Secret | Eksempel | Beskrivelse |
|--------|----------|-------------|
| `TIDSBANKEN_FIRMA_ID` | `67201` | Firma-ID ved første innlogging |
| `TIDSBANKEN_FIRMA_PASSWORD` | *(ditt passord)* | Firmapassord |
| `TIDSBANKEN_ANSATT_ID` | `25` | Service-bruker (ansattnummer) |
| `TIDSBANKEN_ANSATT_PIN` | *(din PIN)* | PIN for service-bruker |

**Aldri** legg passord i kildekode eller git. Roter passord hvis de har vært delt i chat.

## Flyt

1. `GET auth.tidsbanken.net/api/Authorize/Firma?navn=…&passord=…`
2. `GET auth.tidsbanken.net/api/Authorize/AnsattIdOgPin?ansattId=…&pin=…`
3. `GET min.tidsbanken.net/api/planlegging/ansattpanel/ansattliste`
4. For innstemplede: `GET min.tidsbanken.net/api/timelinje/TimelinjeInnstemplet/ForAnsattpanel/{id}`

## Cron (anbefalt hvert 5. min)

Kall edge function `tidsbanken-sync` med service role eller la appen trigge ved åpning av `/Online`.

## App

- Aktiver under **Infoskjerm → Koble Tidsbanken (web)**
- Infoskjerm: `https://drifpro.no/Online` (innlogget)
