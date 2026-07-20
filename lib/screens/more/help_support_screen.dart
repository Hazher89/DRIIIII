import 'package:flutter/material.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';
import 'driftpro_platform_catalog.dart';
import 'widgets/info_page_scaffold.dart';

/// Støtte og veiledning — egen side uten faner.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return InfoPageScaffold(
      title: 'Hjelp & støtte',
      subtitle: 'Veiledning, funksjoner og kontakt for ${AppStrings.appName}',
      icon: Icons.support_agent,
      children: [
        InfoContactCard(
          email: DriftProPlatformCatalog.supportEmail,
          hint:
              'Har du spørsmål om innlogging, ruter, HMS, fravær eller tilganger? '
              'Send e-post til support — vi svarer så raskt vi kan.',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => launchInfoUrl(DriftProPlatformCatalog.supportUrl),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Åpne support-side (hazher.no)'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => launchInfoEmail(
            DriftProPlatformCatalog.supportEmail,
            subject: 'DriftPro — støtte',
          ),
          icon: const Icon(Icons.mail_outline),
          label: Text('Send e-post til ${DriftProPlatformCatalog.supportEmail}'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        const SizedBox(height: 16),
        const InfoSection(
          title: 'Kom i gang',
          icon: Icons.rocket_launch_outlined,
          paragraphs: [
            '${AppStrings.appName} er en skybasert plattform for hele bedriften. '
            'Du logger inn med ansattnummer og passord (eller partner-brukernavn). '
            'Konto opprettes av administrator — det er ikke offentlig selvregistrering.',
          ],
          bullets: [
            'Dashbord: daglig oversikt over fravær, avvik og HMS',
            'Fravær: søk ferie og registrer egenmelding — leder godkjenner',
            'HMS: meld avvik med bilde, fyll ut SJA og se vernerunder',
            'Mer: personalmappe, profil og denne hjelpesiden',
          ],
        ),
        const InfoSection(
          title: 'Fravær og ferie',
          icon: Icons.beach_access_outlined,
          paragraphs: [
            'Fraværsmodulen dekker hele livssyklusen fra søknad til godkjenning. '
            'Leder ser ventende saker under Godkjenn, og alle kan bruke kalenderen '
            'for å planlegge ferie uten overlapp i avdelingen.',
          ],
          bullets: [
            'Ferie, egenmelding, sykt barn, permisjon og sykmelding',
            'Saldo og kvoter per ansatt og år',
            'Dobbel kalender: feriekalender og fraværskalender',
            'Røde dager og regelhjelp fra Lovdata innebygd',
            'Superadmin kan registrere ferie direkte uten godkjenningskø',
          ],
        ),
        const InfoSection(
          title: 'HMS — kvalitet og sikkerhet',
          icon: Icons.health_and_safety_outlined,
          paragraphs: [
            'HMS-huben samler alt arbeid med helse, miljø og sikkerhet. '
            'Modulene er koblet sammen: et avvik kan kobles til risikoanalyse, '
            'og kompetanse utløper med automatiske varsler.',
          ],
          bullets: [
            'Avvik: bilder, GPS, alvorlighetsgrad, tildeling og lukking',
            'Risikoanalyse (ROS) med 5×5 matrise og tiltak',
            'SJA med maler, PPE, farepunkter og digital signatur',
            'Vernerunder med sjekklister og PDF-arkiv',
            'Maskiner & utstyr med service og inspeksjon',
            'Kompetansematrise, kursbevis og utløpsvarsler',
            'DMS for HMS-håndbok og styrende dokumenter',
            'Anonym varsling (whistleblowing) adskilt fra ordinære avvik',
          ],
        ),
        const InfoSection(
          title: 'Partnere, ruter og logistikk',
          icon: Icons.local_shipping_outlined,
          paragraphs: [
            'For transport og distribusjon tilbyr ${AppStrings.appName} et komplett '
            'økosystem fra PDF-import til sjåførportal. Ruter kan komme fra manuell '
            'opplasting, mass auto, AUTO MASS eller SAP e-post innboks (ruter@driftpro.no).',
          ],
          bullets: [
            'Samarbeidspartnere med Brreg, kjøretøy, EU-kontroll og revisjon',
            'Rute-PDF: tildeling, publisering, master-scheduler og flåtedashboard',
            'MAVI-kode og stowing lane hentes automatisk fra PDF',
            'Sjåførportal og eierportal for transportører',
            'SMS til kunder hentet direkte fra rute-PDF',
            'Bilutleie, inspeksjon og felles rutiner/prosedyrer',
            'Sikker fillagring for PDF-er og dokumenter',
          ],
        ),
        const InfoSection(
          title: 'Ruteplanlegging (desktop)',
          icon: Icons.alt_route,
          paragraphs: [
            'DriftPro Dispatch er en dedikert Mac/PC-app for profesjonell ruteplanlegging. '
            'Den bruker samme Supabase-database som web, slik at planlagte ruter og ordre '
            'er synkronisert med partnermodulen og sjåførportalen.',
          ],
          bullets: [
            'Ordre- og ruteoptimalisering',
            'Last mile og VRPTW-støtte',
            'Integrert med partner- og rutedata i skyen',
          ],
        ),
        const InfoSection(
          title: 'Personalmappe og dokumenter',
          icon: Icons.folder_shared_outlined,
          paragraphs: [
            'Under Mer → Personalmappe finner du kursbevis, arbeidsavtaler, sertifikater '
            'og andre filer bedriften har delt med deg. Du kan også laste opp egne '
            'dokumenter (f.eks. kursbevis du har tatt privat) og oppdatere metadata.',
          ],
          bullets: [
            'Oversikt med søk, filter og utløpsvarsler',
            'Opplasting og kategorisering av dokumenter',
            'Kategorier: kursbevis, sertifikat, arbeidsavtale, HMS, annet',
          ],
        ),
        const InfoSection(
          title: 'Tilgang og roller',
          icon: Icons.admin_panel_settings_outlined,
          paragraphs: [
            'Tilgang styres av superadmin under Tilgangskontroll. '
            'Typiske roller er superadmin, admin, leder og ansatt — hver med egne moduler.',
          ],
          bullets: [
            'Superadmin: full tilgang inkl. brukergodkjenning',
            'Leder: godkjenne fravær, se team, HMS-ledelse',
            'Ansatt: egne søknader, avvik, personalmappe og profil',
          ],
        ),
        const InfoSection(
          title: 'Kommende moduler',
          icon: Icons.construction_outlined,
          lead: 'Under aktiv utvikling:',
          bullets: [
            'Sjåfør-app (mobil) — ruter, POD og offline',
            'Lager- & oversiktsapp — kapasitet og plukk',
            'Track & sporing — sanntidssporing og ETA',
          ],
        ),
        ...DriftProPlatformCatalog.groups.map(
          (g) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _FeatureGroupCard(groupTitle: g.title, features: g.features),
          ),
        ),
      ],
      footer: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          '© ${DateTime.now().year} ${DriftProPlatformCatalog.companyName} · ${AppStrings.appName}',
          textAlign: TextAlign.center,
          style: DriftProTheme.caption,
        ),
      ),
    );
  }
}

class _FeatureGroupCard extends StatelessWidget {
  final String groupTitle;
  final List<DriftProFeature> features;

  const _FeatureGroupCard({required this.groupTitle, required this.features});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(groupTitle, style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...features.take(4).map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• ${f.title}: ${f.description}', style: DriftProTheme.bodySm),
                ),
              ),
        ],
      ),
    );
  }
}
