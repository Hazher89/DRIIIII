# Dropbox-lagring for DriftPro

Alle filer lagres i Dropbox-mappen `/DriftPro` når bedriften har koblet OAuth (standard: ingen størrelsesgrense — Supabase brukes kun som reserve).

## Oppsett (én gang)

1. Gå til [dropbox.com/developers](https://www.dropbox.com/developers) → **Create app** → Scoped access → Full Dropbox (eller App folder om du vil begrense).
2. Under **Redirect URIs**, legg til:
   ```
   https://ksnnyccthotjbrmgjgdc.supabase.co/functions/v1/dropbox-storage?action=oauth_callback
   ```
3. I Supabase Dashboard → **Project Settings → Edge Functions → Secrets** (eller CLI):
   - `DROPBOX_APP_KEY`
   - `DROPBOX_APP_SECRET`
   - `DROPBOX_REDIRECT_URI` = samme URL som over
   - `DRIFTPRO_APP_URL` = `https://driftpro.no` (valgfritt, for «tilbake til app»-side)
4. Kjør migrasjon `20260522120000_dropbox_storage.sql`
5. Deploy:
   ```bash
   supabase functions deploy dropbox-storage --no-verify-jwt
   ```
   OAuth-callback trenger `--no-verify-jwt` fordi Dropbox ikke sender Supabase JWT.

## I appen

**Mer → Dropbox-lagring** → «Koble Dropbox». Du logger inn på Dropboxes side (ikke passord i DriftPro).

Etter godkjenning sender Dropbox til Supabase callback, som lagrer token og **videresender til** `https://driftpro.no/?dropbox=connected`. Du trenger ikke endre Redirect URI til driftpro.no.

**App folder:** sett valgfritt secret `DROPBOX_ROOT_FOLDER` = `/` (standard).

## Mappestruktur

```
/DriftPro/company_<uuid>/routes/...
/DriftPro/company_<uuid>/tickets/...
/DriftPro/company_<uuid>/dms/...
```

## API (autentisert bruker)

| action | Metode | Beskrivelse |
|--------|--------|-------------|
| `auth_url` | GET | OAuth-start (kun admin) |
| `oauth_callback` | GET | Dropbox redirect (ingen JWT) |
| `upload` | POST | `{ file_name, category, bytes_base64 }` |
| `temporary_link` | POST | `{ path }` Dropbox-sti |
