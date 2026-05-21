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

På **Rute-planlegger** → knapp **«SAP (n)»** → importer til AUTO MASS-flyt.
