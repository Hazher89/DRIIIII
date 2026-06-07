# Utgående varsel-e-post (`ikkesvar@driftpro.no`)

Sender rader fra `email_outbox`.

**Anbefalt:** Resend API (fungerer fra Supabase Edge Functions / AWS).

**Fallback:** Domeneshop SMTP (blokkeres ofte fra AWS — bruk kun lokalt/dev).

**Påvirker ikke** `ruter@driftpro.no` / Resend Inbound (SAP).

## Supabase secrets (Resend — anbefalt)

Samme API-nøkkel som SAP inbound (`resend-sap-routes-inbound`):

```bash
supabase secrets set RESEND_API_KEY=re_xxxx
supabase secrets set RESEND_FROM=ikkesvar@driftpro.no
supabase secrets set RESEND_FROM_NAME=DriftPro
# Valgfritt:
# supabase secrets set RESEND_REPLY_TO=support@mavilogistikk.no
# supabase secrets set EMAIL_TEST=true
```

Krav i Resend Dashboard:

1. Domene `driftpro.no` verifisert (samme som inbound)
2. Avsender `ikkesvar@driftpro.no` tillatt på domenet

## Fallback SMTP (valgfritt)

```bash
supabase secrets set SMTP_HOST=smtp.domeneshop.no
supabase secrets set SMTP_PORT=587
supabase secrets set SMTP_USER=ikkesvar@driftpro.no
supabase secrets set SMTP_PASS='DITT_PASSORD_HER'
```

Brukes bare hvis `RESEND_API_KEY` mangler.

## Deploy

```bash
supabase functions deploy send-email-outbox
```

Cron kjører workeren hvert minutt via `20260603192500_outbox_workers_cron.sql`.

## Test

```sql
SELECT public.queue_email(
  '<company-uuid>'::uuid,
  'din@epost.no',
  'DriftPro test',
  'Test fra ikkesvar@driftpro.no',
  'test'
);
```

Invoke worker (Dashboard → Edge Functions → send-email-outbox → Invoke).

Respons skal inneholde `"provider":"resend"`.

## Kvoter (Resend Free)

Innkommende (SAP) + utgående (varsler) teller **sammen** mot 3 000/mnd og 100/dag.
