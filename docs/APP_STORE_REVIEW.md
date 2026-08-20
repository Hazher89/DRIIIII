# App Store Connect — DriftPro (offentlig App Store)

Sist oppdatert: 20. august 2026 · App-versjon **1.0.0**

## Status (ærlig)

| Område | Status | Merknad |
|--------|--------|---------|
| Kontosletting i app (5.1.1v) | Klar i app | Profil + Personvern → Slett konto |
| Personvern-URL | Må oppdateres | hazher.no nevner fortsatt kun e-post — se § nedenfor |
| Permission-strenger (Info.plist) | Klar | Uten «Eksempel:» |
| Privacy Manifest | Klar | `PrivacyInfo.xcprivacy` |
| Sign in with Apple | Capability på | Mobil bruker ansattnummer (ikke Google) — 4.8 OK |
| Export compliance | Klar | `ITSAppUsesNonExemptEncryption` = false |
| Demo-konto for review | Manuelt | Sett midlertidig passord før innsending |
| Push / FCM (iOS + Android) | Kode klar, **ikke ferdig konfigurert** | Se «Push-varsler» |

---

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

---

## KRITISK før innsending: oppdater personvernsiden

App Store 5.1.1(v) krever at Privacy Policy beskriver **in-app** kontosletting når den finnes.

Erstatt eller utvid §7 på https://hazher.no/DRIFTPRO/Privacy/ med:

> **Konto og sletting**  
> Du kan slette kontoen direkte i appen: **Profil → Slett konto**, eller **Mer → Personvern → Slett konto permanent** (skriv SLETT for å bekrefte).  
> Dette sletter innloggingen og anonymiserer personopplysninger i profilen. Lovpålagt HMS-/HR-historikk kan oppbevares uten din identitet der det er nødvendig.  
> Du kan også kontakte leder/administrator eller kontakt@hazher.no.

Uten denne teksten kan Apple avvise selv om appen har sletteknapp.

---

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

Also available: employee number login only on mobile (Google only on web).

Partner portal uses a separate username/password (admin-provisioned) — not needed for core review.

Account deletion (App Store 5.1.1v):
Min profil → Slett konto (type SLETT), or Mer → Personvern → Slett konto permanent.
This deletes the auth account and anonymizes personal profile data. Legally required HMS/HR records may be retained without personal identifiers.

Permissions are requested only when the related feature is used (camera for photos/scan, photos for attachments, location when the user taps GPS, notifications for driver route alerts). Purpose strings live in Info.plist — no custom in-app permission popups before the system dialog.

Privacy Policy: https://hazher.no/DRIFTPRO/Privacy/
Support: https://hazher.no/DRIFTPRO/Support/
```

---

## Sign in with Apple (Xcode / Apple Developer)

- Capability: **Sign in with Apple** (`Runner.entitlements`)
- Bundle ID: `no.driftpro.driftpro`
- Supabase → Authentication → Providers → Apple: Client ID = `no.driftpro.driftpro` (native iOS)
- På **mobil** brukes ansattnummer/passord (ikke Google) → Guideline 4.8 (tredjepartsinnlogging) utløses ikke
- Google finnes kun på **web**

## Deep link / OAuth-retur

`no.driftpro.driftpro://login-callback/`

## App Privacy (Connect)

Linked to user: Yes · Used for Tracking: No · Purpose: App Functionality  
(for Name, Email, Phone, Precise Location, Photos, Other User Content, User ID, Device ID)

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

1. Signing Team aktivt (f.eks. `644LC648DB`)
2. Capabilities: **Sign in with Apple** på
3. Bundle `no.driftpro.driftpro`, versjon 1.0.0
4. Test på fysisk iPhone: ansattnummer-login + Slett konto-flyt
5. Push: kun aktiver **Push Notifications** + APNs når Firebase er ferdig (se under)

---

## Push-varsler (Android + iOS) — status

### Det som er på plass i koden

- `firebase_messaging` + lokal kanal `partner_routes`
- `POST_NOTIFICATIONS` (Android 13+)
- Token lagres via `upsert_push_device` (platform `android` / `ios`)
- Sjåførportal ber om varsel-tillatelse etter login
- Edge `send-push-outbox` sender via FCM når secret finnes
- DB: `user_push_devices` + `push_outbox`

### Det som mangler for at push faktisk virker

1. **Firebase-prosjekt** med Android-app (`no.driftpro.driftpro`) og iOS-app
2. Filene `android/app/google-services.json` og `ios/Runner/GoogleService-Info.plist` (ikke i repo)
3. Bygg med FlutterFire / dart-defines (`FIREBASE_API_KEY`, `FIREBASE_APP_ID`, …) — uten dette er `FirebaseConfig.isConfigured == false` og FCM startes ikke
4. Supabase secret **`FCM_SERVER_KEY`** (eller bedre: migrer til FCM HTTP v1 — legacy key er deprecated)
5. Deploy `send-push-outbox`
6. **iOS:** APNs-nøkkel i Firebase + Xcode capability **Push Notifications** + `aps-environment`

**Konklusjon:** Android-push er **ikke «live»** før Firebase + secrets er satt. Appen faller tilbake til lokale/realtime-varsler der det er implementert.

### Anbefalt rekkefølge for push (etter App Store-godkjenning OK)

```bash
# 1) flutterfire configure
# 2) legg google-services.json / GoogleService-Info.plist
# 3) Xcode: Push Notifications + Background Modes → Remote notifications
# 4) Firebase Console: last opp APNs Auth Key
# 5) supabase secrets set FCM_SERVER_KEY=...
# 6) supabase functions deploy send-push-outbox
```

---

## Google Play (kort)

- App-label: **DriftPro**
- Release signing: bytt fra debug-keystore før Play-release (`android/app/build.gradle.kts`)
- Samme Firebase-steg som over for push
