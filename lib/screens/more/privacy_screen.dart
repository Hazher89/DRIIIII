import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../profile/delete_own_account_dialog.dart';
import 'driftpro_platform_catalog.dart';
import 'widgets/info_page_scaffold.dart';

/// Personvern — egen side.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return InfoPageScaffold(
      title: 'Personvern',
      subtitle: 'GDPR, databehandling og dine rettigheter',
      icon: Icons.privacy_tip_outlined,
      children: [
        InfoContactCard(
          email: DriftProPlatformCatalog.privacyEmail,
          hint:
              'Spørsmål om personvern, innsyn eller sletting? Kontakt oss på e-post.',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => launchInfoUrl(DriftProPlatformCatalog.privacyPolicyUrl),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Åpne personvernerklæring (hazher.no)'),
          style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => launchInfoUrl(DriftProPlatformCatalog.termsOfUseUrl),
          icon: const Icon(Icons.description_outlined),
          label: const Text('Vilkår for bruk (hazher.no)'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => launchInfoUrl(DriftProPlatformCatalog.supportUrl),
          icon: const Icon(Icons.support_agent_outlined),
          label: const Text('Support (hazher.no)'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => launchInfoEmail(
            DriftProPlatformCatalog.privacyEmail,
            subject: 'DriftPro — personvern',
          ),
          icon: const Icon(Icons.mail_lock_outlined),
          label: Text(DriftProPlatformCatalog.privacyEmail),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
        ),
        const SizedBox(height: 16),
        const InfoSection(
          title: 'Behandlingsansvarlig',
          icon: Icons.business_outlined,
          paragraphs: [
            '${DriftProPlatformCatalog.companyName} er behandlingsansvarlig for '
            'personopplysninger som behandles i ${AppStrings.appName} på vegne av '
            'kundens bedrift. Den enkelte bedrift (arbeidsgiver) er ansvarlig for '
            'at bruk av plattformen er i tråd med interne rutiner og lovverk.',
          ],
        ),
        const InfoSection(
          title: 'Formål med behandlingen',
          icon: Icons.flag_outlined,
          bullets: [
            'Administrere arbeidsforhold: fravær, ferie, profiler og avdelinger',
            'HMS-arbeid: avvik, risikoanalyse, SJA, vernerunder og kompetanse',
            'Logistikk og rutedrift: partnerdata, rute-PDF og sjåførportal',
            'Varsling via SMS og e-post der dette er aktivert',
            'Dokumenthåndtering i personalmappe og DMS',
            'Sikkerhet: innlogging, tilgangsstyring og revisjon',
          ],
        ),
        const InfoSection(
          title: 'Hvilke opplysninger behandles',
          icon: Icons.storage_outlined,
          bullets: [
            'Identifikasjon: navn, ansattnummer, e-post, telefon, avdeling, rolle',
            'HR: fødselsdato, adresse, nødkontakt, fraværshistorikk og feriekvoter',
            'HMS: avvikstekst, bilder, GPS ved innrapportering, ROS og SJA-data',
            'Kompetanse: kursbevis, sertifikater og utløpsdatoer',
            'Teknisk: innloggingstidspunkt, enhetstype og logger via Supabase Auth',
            'Filer: PDF, bilder og dokumenter lagret sikkert per bedrift',
          ],
        ),
        const InfoSection(
          title: 'Rettslig grunnlag',
          icon: Icons.gavel_outlined,
          paragraphs: [
            'Behandlingen skjer primært på grunnlag av arbeidsavtale og berettiget '
            'interesse (HMS, drift og sikkerhet). For HMS og avvik kan det også være '
            'nødvendig for å oppfylle lovpålagte plikter etter arbeidsmiljøloven.',
          ],
        ),
        const InfoSection(
          title: 'Dine rettigheter (GDPR art. 15–22)',
          icon: Icons.person_outline,
          bullets: [
            'Innsyn: se egne data via Min profil og personalmappe',
            'Retting: be leder eller superadmin om å korrigere feil',
            'Sletting: bruk «Slett konto» under Min profil / denne siden',
            'Begrensning og protest: kontakt behandlingsansvarlig',
            'Dataportabilitet: dokumenter kan leveres ut ved forespørsel',
            'Klage til Datatilsynet dersom du mener behandlingen er ulovlig',
          ],
        ),
        InfoSection(
          title: 'Slett konto',
          icon: Icons.person_off_outlined,
          paragraphs: [
            '${AppStrings.appName} er en bedriftsapp. Konto opprettes vanligvis av '
            'administrator. Du kan likevel slette din egen innlogging og '
            'personopplysninger direkte i appen (App Store-krav).',
          ],
          bullets: const [
            'Gå til Min profil → Slett konto, eller bruk knappen under',
            'Skriv SLETT for å bekrefte',
            'Lovpålagt HMS-/HR-historikk kan oppbevares uten din identitet',
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FilledButton.icon(
            onPressed: () => showDeleteOwnAccountDialog(context),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Slett konto permanent'),
            style: FilledButton.styleFrom(
              backgroundColor: DriftProTheme.error,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ),
        const InfoSection(
          title: 'Sikkerhetstiltak',
          icon: Icons.shield_outlined,
          bullets: [
            'Row Level Security — hver bedrift isoleres i databasen',
            'Rollebasert tilgang (superadmin, admin, leder, ansatt)',
            'Kryptering i transitt (HTTPS/TLS) og hos underleverandører',
            'Sikker fillagring med OAuth der dette er aktivert',
            'Infoskjerm-modus uten navn på felles skjerm',
            'Anonym varsling adskilt fra identifiserbare avvik',
            'Tilgang til avviksbilder og dokumenter kun for autoriserte brukere',
          ],
        ),
        const InfoSection(
          title: 'Lagring og sletting',
          icon: Icons.schedule_outlined,
          paragraphs: [
            'Data lagres så lenge arbeidsforholdet består og det er nødvendig for '
            'formålet. HMS- og fraværsdata kan ha lengre oppbevaring etter lov og '
            'interne rutiner. Ved avsluttet kundeforhold slettes eller anonymiseres '
            'data etter avtale.',
          ],
          bullets: [
            'Filer lagres i bedriftens godkjente skylagring',
            'Metadata og struktur ligger i Supabase (EU-region)',
            'Utløpte kompetansebevis flagges automatisk i systemet',
          ],
        ),
        const InfoSection(
          title: 'Underleverandører (databehandlere)',
          icon: Icons.cloud_outlined,
          bullets: [
            'Supabase — database, autentisering, edge functions og sanntid',
            'Firebase — push-varsler der dette er aktivert',
            'Dropbox — fillagring når bedriften har koblet lagring',
            'Mavi / SMS-gateway — varsler der dette er konfigurert',
            'Resend — e-post for SAP ruteinnboks og systemmeldinger',
          ],
        ),
        const InfoSection(
          title: 'Informasjonskapsler og nettleser',
          icon: Icons.cookie_outlined,
          paragraphs: [
            'Webversjonen bruker nødvendige sesjonskapsler for innlogging via Supabase Auth. '
            'Vi bruker ikke tredjeparts reklamekapsler. Lokal lagring kan brukes for '
            'tema (mørk modus) og brukerpreferanser.',
          ],
        ),
        const InfoSection(
          title: 'Barn og sensitive data',
          icon: Icons.child_care_outlined,
          paragraphs: [
            '${AppStrings.appName} er en arbeidsplattform og er ikke rettet mot barn. '
            'Sensitive personopplysninger (f.eks. helseopplysninger i sykmelding/fravær) '
            'behandles med begrenset tilgang til leder og HR-roller.',
          ],
        ),
      ],
      footer: Text(
        'Sist oppdatert: ${DateTime.now().year} · ${DriftProPlatformCatalog.companyName}\n'
        '${DriftProPlatformCatalog.privacyPolicyUrl}',
        textAlign: TextAlign.center,
        style: DriftProTheme.caption,
      ),
    );
  }
}
