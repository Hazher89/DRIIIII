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
| Terms | https://hazher.no/DRIFTPRO/Terms/ |

## Demo-konto for Apple Review (påkrevd)

Appen har ikke offentlig selvregistrering. Opprett midlertidig review-passord før innsending.

1. I DriftPro: sørg for at ansatt **25** (eller egen review-bruker) er aktiv.
2. Sett et midlertidig, sterkt passord.
3. Test: **MAVI ansatte** → ansattnummer + passord → inn i appen.
4. Lim inn Review Notes under.

```
DriftPro is a workplace HMS/HR/logistics app used by companies (e.g. Mavi Logistikk AS) and their partners.

Primary login (recommended for review):
1. Tap «MAVI ansatte»
2. Employee number: 25
3. Password: [sett midlertidig review-passord før innsending]

Also available: Sign in with Apple (native on iOS).

Partner portal uses a separate username/password (admin-provisioned) — not needed for core review.

Account deletion (App Store 5.1.1v):
Min profil → Slett konto (type SLETT), or Mer → Personvern → Slett konto permanent.
This deletes the auth account and anonymizes personal profile data. Legally required HMS/HR records may be retained without personal identifiers.

Permissions are requested only when the related feature is used (camera for photos/scan, photos for attachments, location when the user taps GPS, notifications in driver route alerts). Purpose strings live in Info.plist — no custom in-app permission popups.

Privacy Policy: https://hazher.no/DRIFTPRO/Privacy/
Support: https://hazher.no/DRIFTPRO/Support/
```

## Sign in with Apple (Xcode / Apple Developer)

- Capability: **Sign in with Apple** (Runner.entitlements har `com.apple.developer.applesignin`)
- Bundle ID: `no.driftpro.driftpro`
- Supabase Dashboard → Authentication → Providers → Apple: aktiver og legg til Client ID = `no.driftpro.driftpro` (native iOS)

## Deep link / OAuth-retur

Redirect URL som må være tillatt i Supabase Auth:

`no.driftpro.driftpro://login-callback/`

## App Privacy (Connect)

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

## Xcode-sjekkliste før Archive

1. Signing Team: `644LC648DB` (eller aktivt team)
2. Capabilities: **Sign in with Apple** (på)
3. Push/FCM: bevisst utsatt — ikke krev remote notifications i denne innsendingen
4. Test på fysisk iPhone: ansattnummer-login + Fortsett med Apple + Slett konto-flyt

## Oppdater Privacy-side (hazher.no) før innsending

Personvernsiden må nevne **in-app kontosletting** (App Store 5.1.1v), f.eks.:

> Du kan slette kontoen i appen: Min profil → Slett konto, eller Mer → Personvern → Slett konto permanent (skriv SLETT).

Nåværende tekst som kun ber brukeren sende e-post er ikke nok alene.
