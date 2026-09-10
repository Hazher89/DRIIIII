# Microsoft Graph → SAP rute-innboks

Synker PDF-er fra **Office 365** (`driftpro@mavilogistikk.no`) inn i `sap_route_inbox`.

## Forutsetninger (Azure)

1. App registration: **DriftPro Route Inbox** (single tenant MAVI Logistikk AS)
2. Client secret opprettet
3. API permission: Microsoft Graph **Application** → `Mail.Read` + **`Mail.Send`**
4. **Grant admin consent**
5. (Anbefalt) Application Access Policy som begrenser appen til kun `driftpro@mavilogistikk.no`

> `Mail.Send` brukes også av `send-email-outbox` (utgående varsler fra samme postkasse).

## Supabase secrets

Sett i **Project Settings → Edge Functions → Secrets** (ikke commit):

| Secret | Verdi |
|--------|--------|
| `MS_GRAPH_TENANT_ID` | Directory (tenant) ID fra Azure |
| `MS_GRAPH_CLIENT_ID` | Application (client) ID |
| `MS_GRAPH_CLIENT_SECRET` | Client secret **Value** (ikke Secret ID) |
| `MS_GRAPH_MAILBOX` | `driftpro@mavilogistikk.no` |
| `SAP_ROUTES_COMPANY_ID` | MAVI company UUID (samme som Resend-flyt) |
| `SAP_GRAPH_SYNC_SECRET` | valgfri delt nøkkel for å beskytte endepunktet |

## Deploy

```bash
supabase functions deploy ms-graph-sap-routes-sync --no-verify-jwt
```

## Kjør sync manuelt

```bash
curl -X POST \
  'https://ksnnyccthotjbrmgjgdc.supabase.co/functions/v1/ms-graph-sap-routes-sync' \
  -H 'Content-Type: application/json' \
  -H 'x-sap-graph-sync-secret: DIN_SYNC_SECRET' \
  -d '{"hours": 168, "markRead": true}'
```

Henter **alle** mail i tidsvinduet (paginert, ingen `limit`). Filter i kode: avsender `*@elkjop.no`, emne `Backup Form`, PDF-vedlegg. Dropbox med fallback til Supabase `documents`.

## SAP

Send Backup Form til **`driftpro@mavilogistikk.no`** (eller forward fra `ruter@driftpro.no`).
