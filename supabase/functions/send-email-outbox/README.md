# Domeneshop SMTP — varsel-e-post (`ikkesvar@driftpro.no`)

Sender rader fra `email_outbox` via `smtp.domeneshop.no`.

**Påvirker ikke** `ruter@driftpro.no` / Resend Inbound (SAP).

## Supabase secrets

```bash
supabase secrets set SMTP_HOST=smtp.domeneshop.no
supabase secrets set SMTP_PORT=587
supabase secrets set SMTP_USER=ikkesvar@driftpro.no
supabase secrets set SMTP_PASS='DITT_PASSORD_HER'
supabase secrets set SMTP_FROM=ikkesvar@driftpro.no
supabase secrets set SMTP_FROM_NAME=DriftPro
# Valgfritt test (markerer som sendt uten å sende):
# supabase secrets set EMAIL_TEST=true
```

## Deploy

```bash
supabase db push
supabase functions deploy send-email-outbox
```

## Cron

Samme mønster som `send-sms-outbox`: kall funksjonen hvert minutt (Supabase Cron / pg_cron).

## SPF

Legg Domeneshop sin SPF-verdi i DNS for `driftpro.no` **sammen med** Resend (ikke erstatt).

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

Deretter invoke `send-email-outbox` (Dashboard eller `supabase functions invoke send-email-outbox`).
