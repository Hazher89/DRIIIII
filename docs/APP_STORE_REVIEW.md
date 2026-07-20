# App Store Connect — DriftPro (offentlig App Store)

## Distribusjon

Sett **Public — Discoverable by anyone on the App Store** under Pricing and Availability  
(bytt bort fra Private før innsending — kan ikke endres etter godkjenning).

Fjern huk for Vision Pro / Mac hvis dere ikke leverer native dit.

## URL-er

| Felt | URL |
|------|-----|
| Privacy Policy | https://hazher.no/DRIFTPRO/Privacy/ |
| Support URL (App Information) | https://hazher.no/DRIFTPRO/Support/ |
| Marketing | https://hazher.no/DRIFTPRO/ |

## Review Notes (lim inn)

```
DriftPro is a workplace HMS/HR/logistics app used by companies (e.g. Mavi Logistikk AS) and their partners.

Login: employee number + password (accounts are provisioned by the employer — no public self-registration in the app).
Partner portal: username + password (also admin-provisioned).

Demo account for App Review:
- Employee number: 25
- Password: [sett midlertidig review-passord før innsending]

Account deletion (App Store 5.1.1v):
Min profil → Slett konto (type SLETT), or Mer → Personvern → Slett konto permanent.
This deletes the auth account and anonymizes personal profile data. Legally required HMS/HR records may be retained without personal identifiers.

Permissions are requested with in-app explanations before system prompts: notifications, camera, photos, location, microphone.

Privacy Policy: https://hazher.no/DRIFTPRO/Privacy/
Support: https://hazher.no/DRIFTPRO/Support/
```

## App Privacy

Linked to user: Yes · Used for Tracking: No · Purpose: App Functionality  
(for Name, Email, Phone, Precise Location, Photos, Other User Content, User ID, Device ID, Product Interaction, Crash/Performance om valgt)

## Age Rating

NO på Parental Controls, Age Assurance, Web Access, UGC, Social, Chat, Advertising.  
Ingen mature themes.

## Deploy før innsending

```bash
supabase functions deploy delete-own-account
# deretter Archive/IPA via Xcode eller flutter build ipa
```

## Export compliance

`ITSAppUsesNonExemptEncryption` = false (kun HTTPS).
