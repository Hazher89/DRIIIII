# Resend Inbound — SAP rute-PDF (`ruter@driftpro.no`)

Mottar e-post fra SAP (`Backup Form`, avsender `*@elkjop.no`) og lagrer PDF i `sap_route_inbox`.

## 1. Resend Dashboard

1. [resend.com](https://resend.com) → **Domains** → legg til `driftpro.no`
2. Sett **DNS** (SPF, DKIM) som Resend viser
3. Under domenet: **Inbound** → aktiver mottak
4. Legg **MX**-post for mottak (Resend viser verdi, f.eks. `inbound-smtp…`)
5. Opprett adresse **`ruter@driftpro.no`** (eller alias som peker dit)

## 2. Webhook

1. **Webhooks** → Add endpoint  
   - URL: `https://<project-ref>.supabase.co/functions/v1/resend-sap-routes-inbound`  
   - Event: `email.received`  
2. Kopier **Signing secret** → Supabase secret `RESEND_WEBHOOK_SECRET`

## 3. Supabase secrets

```bash
supabase secrets set RESEND_API_KEY=re_xxxx
supabase secrets set RESEND_WEBHOOK_SECRET=whsec_xxxx
supabase secrets set SAP_ROUTES_COMPANY_ID=00000000-0000-0000-0000-000000000000
```

(`SAP_ROUTES_COMPANY_ID` = MAVI / DriftPro company UUID)

## 4. Deploy

```bash
supabase db push
supabase functions deploy resend-sap-routes-inbound --no-verify-jwt
```

## 5. SAP

Konfigurer SAP til å sende **Backup Form** med PDF-vedlegg til:

**ruter@driftpro.no**

Krav:
- Avsender: `*@elkjop.no`
- Emne: `Backup Form`
- Vedlegg: PDF (typisk `ZTM_FO_BACKUP_…`)

## 6. DriftPro

På **Rute-planlegger** → knapp **«Ruter fra SAP (n)»** → importer til AUTO MASS-flyt.

## 7. Feilsøking

**Resend viser e-post, men knappen er tom**

1. Sjekk at webhook peker på  
   `https://ksnnyccthotjbrmgjgdc.supabase.co/functions/v1/resend-sap-routes-inbound`  
   med event `email.received`, og at **Signing secret** = `RESEND_WEBHOOK_SECRET`.
2. Dropbox-feil blokkerer ikke lenger import (fallback til Supabase `documents`).
3. **Replay** av siste mottatte e-post (f.eks. etter webhook-nedetid):

```bash
supabase secrets set SAP_REPLAY_SECRET=din-hemmelige-nøkkel
supabase functions deploy resend-sap-routes-replay --no-verify-jwt

curl -X POST 'https://ksnnyccthotjbrmgjgdc.supabase.co/functions/v1/resend-sap-routes-replay' \
  -H "x-sap-replay-secret: din-hemmelige-nøkkel" \
  -H "Content-Type: application/json" \
  -d '{"hours": 72, "limit": 50}'
```
