import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/driftpro_brand_logo.dart';
import 'driftpro_platform_catalog.dart';
import 'widgets/info_page_scaffold.dart';

/// Om DriftPro — egen side med full produktbeskrivelse.
class AboutDriftProScreen extends StatelessWidget {
  const AboutDriftProScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InfoPageScaffold(
      title: 'Om ${AppStrings.appName}',
      subtitle: DriftProPlatformCatalog.tagline,
      icon: Icons.info_outline,
      children: [
        const Center(
          child: DriftProBrandLogo(
            density: DriftProBrandDensity.comfortable,
            alignment: Alignment.center,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            DriftProPlatformCatalog.versionLabel,
            style: DriftProTheme.labelLg.copyWith(
              color: DriftProTheme.primaryGreen,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const InfoSection(
          title: 'Visjon',
          icon: Icons.auto_awesome,
          paragraphs: [
            '${AppStrings.appName} skal være den mest komplette nordiske plattformen '
            'for HMS, personaladministrasjon, logistikk og rutedrift — fra verneombudet '
            'på gulvet til ruteplanleggeren på kontoret og sjåføren i bilen.',
            'Vi bygger én sannhet i skyen: samme data for ledelse, HR, HMS, partnere '
            'og sjåfører — uten Excel-kaos og e-postvedlegg.',
          ],
        ),
        const InfoSection(
          title: 'Hva er DriftPro?',
          icon: Icons.hub_outlined,
          paragraphs: [
            '${AppStrings.appName} er en modulær enterprise-plattform levert av '
            '${DriftProPlatformCatalog.companyName}. Kjernen er en sikker '
            'Supabase-database med Flutter-apper for web, desktop og (kommende) mobil.',
            'Filer og dokumenter lagres sikkert i skyen med automatisk organisering '
            'per bedrift og funksjon.',
          ],
          bullets: [
            'Ett login — tilpasset moduler per rolle',
            'Norsk språk og Lovdata-integrasjon i fraværsmodulen',
            'Skalerer fra 10 til 1000+ ansatte',
            'Partner- og transportmodul for distribusjon og last mile',
          ],
        ),
        const InfoSection(
          title: 'Produktportefølje',
          icon: Icons.apps,
          lead: 'Live i dag:',
          bullets: [
            'DriftPro Web — HMS, HR, fravær, partnere, undersøkelser (driftpro.no)',
            'DriftPro Dispatch — desktop ruteplanlegger for Mac og PC',
            'Sjåførportal — ruter, PDF og daglig arbeidsflyt for sjåfører',
            'Eierportal — for transportører og bil-eiere',
            'Partnermodul — Brreg, MAVI, SMS, bilutleie og rute-PDF',
          ],
        ),
        const InfoSection(
          title: 'Under utvikling',
          icon: Icons.construction,
          bullets: [
            'Sjåfør-app (iOS/Android) — mobiloptimalisert med offline og POD',
            'Lager- & oversiktsapp — sanntidsoversikt over lager og kapasitet',
            'Track & sporing — GPS-sporing, ETA og kundevarsling',
            'Utvidet telemetri — temperatur, kjøretøydata og avviksanalyse',
          ],
        ),
        const InfoSection(
          title: 'Moduler i detalj',
          icon: Icons.view_module_outlined,
          paragraphs: [
            'Plattformen består av over 30 integrerte funksjoner. Her er hovedområdene:',
          ],
          bullets: [
            'Dashbord med KPI, hurtighandlinger og aktivitetsfeed',
            'Fravær: ferie, egenmelding, godkjenning, kalender, saldo, Lovdata',
            'HMS: avvik, ROS, SJA, vernerunder, utstyr, kompetanse, DMS',
            'Ansatte: profiler, avdelinger, organisasjonskart, personalmappe',
            'Partnere: register, ruter, mass auto, SAP-innboks, flåtedashboard',
            'Varsler: SMS/e-post, Mavi-integrasjon, hendelseskatalog',
            'Admin: tilgangskontroll, brukergodkjenning og infoskjerm',
            'Undersøkelser, anonym varsling og online-tilstedeværelse',
          ],
        ),
        const InfoSection(
          title: 'Ruteplanlegging og logistikk',
          icon: Icons.alt_route,
          paragraphs: [
            '${AppStrings.appName} er ikke bare HMS — det er et komplett ruteplanleggingssystem. '
            'DriftPro Dispatch optimaliserer ruter på desktop, mens webmodulen håndterer '
            'PDF-import, tildeling til kjøretøy, publisering til sjåfør og SMS til sluttkunde.',
            'SAP-ruter kan mottas automatisk via e-post (backup form fra @elkjop.no) '
            'og prosesseres i innboksen før tildeling.',
          ],
        ),
        const InfoSection(
          title: 'Teknologi',
          icon: Icons.code,
          bullets: [
            'Frontend: Flutter (web, macOS, Windows, Linux, mobil)',
            'Backend: Supabase (PostgreSQL, Auth, Realtime, Edge Functions)',
            'Integrasjoner: Mavi, Brreg, Resend, Lovdata-regler',
            'Sikkerhet: RLS, JWT, rollebasert tilgang',
          ],
        ),
        const InfoSection(
          title: 'For hvem?',
          icon: Icons.groups,
          paragraphs: [
            '${AppStrings.appName} er bygget for logistikkbedrifter, lager og distribusjon, '
            'transportpartnere og virksomheter med HMS-krav. Typiske brukere:',
          ],
          bullets: [
            'Superadmin / daglig leder — full oversikt og konfigurasjon',
            'HR og lønn — fravær, ansatte, personalmappe',
            'HMS-ansvarlig / verneombud — avvik, ROS, SJA, vernerunder',
            'Transportleder — partnere, ruter, tildeling, SMS',
            'Sjåfør og lager — portal, personalmappe, avvik',
          ],
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? DriftProTheme.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
            ),
          ),
          child: Column(
            children: [
              Text('Utviklet av', style: DriftProTheme.caption),
              const SizedBox(height: 4),
              Text(
                DriftProPlatformCatalog.companyName,
                style: DriftProTheme.headingSm,
              ),
              const SizedBox(height: 8),
              Text(
                'driftpro.no',
                style: DriftProTheme.bodyMd.copyWith(color: DriftProTheme.primaryGreen),
              ),
            ],
          ),
        ),
      ],
      footer: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          '© ${DateTime.now().year} ${DriftProPlatformCatalog.companyName}. '
          'Alle rettigheter forbeholdt.',
          textAlign: TextAlign.center,
          style: DriftProTheme.caption,
        ),
      ),
    );
  }
}
