# Utgående varsel-e-post

Sender rader fra `email_outbox`.

**Anbefalt (nytt):** Microsoft Graph `Mail.Send` via samme app som SAP-innboks  
(`driftpro@mavilogistikk.no` — DriftPro Route Inbox).

**Fallback:** Resend API, deretter Domeneshop SMTP.

## Prioritet

1. **Graph** — hvis `MS_GRAPH_TENANT_ID` + `MS_GRAPH_CLIENT_ID` + `MS_GRAPH_CLIENT_SECRET` er satt  
2. **Resend** — hvis `RESEND_API_KEY` er satt  
3. **SMTP** — hvis `SMTP_USER` / `SMTP_PASS` er satt  

## Azure (Graph)

1. App: **DriftPro Route Inbox**
2. Application permission: `Mail.Read` (mottak) + **`Mail.Send`** (utsending)
3. **Grant admin consent**
4. (Anbefalt) Application Access Policy begrenset til `driftpro@mavilogistikk.no`

## Supabase secrets (Graph — anbefalt)

Samme som SAP sync (allerede satt hvis mottak fungerer):

| Secret | Verdi |
|--------|--------|
| `MS_GRAPH_TENANT_ID` | Directory (tenant) ID |
| `MS_GRAPH_CLIENT_ID` | Application (client) ID |
| `MS_GRAPH_CLIENT_SECRET` | Client secret Value |
| `MS_GRAPH_MAILBOX` | `driftpro@mavilogistikk.no` (valgfritt, default) |
| `MS_GRAPH_FROM_NAME` | `DriftPro` (valgfritt) |
| `MS_GRAPH_REPLY_TO` | f.eks. `support@mavilogistikk.no` (valgfritt) |
| `EMAIL_TEST` | `true` for tørrkjøring uten faktisk send |

## Fallback Resend (valgfritt)

```bash
supabase secrets set RESEND_API_KEY=re_xxxx
supabase secrets set RESEND_FROM=ikkesvar@driftpro.no
```

Brukes bare hvis Graph-secrets mangler.

## Deploy

```bash
supabase functions deploy send-email-outbox
```

Cron kjører workeren hvert minutt via `20260603192500_outbox_workers_cron.sql`.

## Test

Kjør workeren (service role / cron):

```bash
curl -X POST \
  'https://ksnnyccthotjbrmgjgdc.supabase.co/functions/v1/send-email-outbox' \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H 'Content-Type: application/json' \
  -d '{}'
```

Respons skal inneholde `"provider":"graph"` og `"from":"\"DriftPro\" <driftpro@mavilogistikk.no>"`.

Sett én test-rad i `email_outbox` med din egen adresse, kjør funksjonen, sjekk innboks + Sent Items i Outlook for `driftpro@mavilogistikk.no`.
