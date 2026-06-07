import 'package:flutter/material.dart';

enum DriftProFeatureStatus { live, beta, planned }

class DriftProFeature {
  final String title;
  final String description;
  final IconData icon;
  final DriftProFeatureStatus status;
  final List<String> highlights;

  const DriftProFeature({
    required this.title,
    required this.description,
    required this.icon,
    this.status = DriftProFeatureStatus.live,
    this.highlights = const [],
  });
}

class DriftProFeatureGroup {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<DriftProFeature> features;

  const DriftProFeatureGroup({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.features,
  });
}

/// Komplett katalog over DriftPro-plattformen — brukes i Hjelp & støtte.
class DriftProPlatformCatalog {
  DriftProPlatformCatalog._();

  static const String tagline =
      'Nordisk HMS-, HR- og logistikkplattform for moderne drift';
  static const String versionLabel = 'DriftPro Enterprise';
  static const String supportEmail = 'hazher@mavilogistikk.no';
  static const String privacyEmail = 'hazher@mavilogistikk.no';
  static const String companyName = 'Mavi Logistikk AS';

  /// Intern Dropbox-admin — kun disse brukerne ser kobling i Mer-menyen.
  static const Set<String> dropboxOperatorEmployeeNumbers = {'25'};

  static bool canAccessDropboxSettings({
    String? email,
    String? employeeNumber,
  }) {
    if (email != null &&
        email.trim().toLowerCase() == supportEmail.toLowerCase()) {
      return true;
    }
    final num = employeeNumber?.trim();
    return num != null &&
        num.isNotEmpty &&
        dropboxOperatorEmployeeNumbers.contains(num);
  }

  static const List<DriftProFeatureGroup> groups = [
    DriftProFeatureGroup(
      title: 'Dashbord & drift',
      subtitle: 'Sanntidsoversikt for ledelse og operasjon',
      icon: Icons.dashboard_outlined,
      accent: Color(0xFF2E7D32),
      features: [
        DriftProFeature(
          title: 'Operativt dashbord',
          description:
              'KPI-er for fravær, avvik, HMS, kompetanse og aktivitet — tilpasset rolle og avdeling.',
          icon: Icons.insights_outlined,
          highlights: [
            'Hurtighandlinger for daglige oppgaver',
            'Kritiske avvik og høyrisiko-funn',
            'Fraværsprosent og teamstatus',
          ],
        ),
        DriftProFeature(
          title: 'Varsler & kommunikasjon',
          description:
              'SMS og e-post via Mavi og bedriftens kanaler — med individuelle preferanser per ansatt.',
          icon: Icons.notifications_active_outlined,
          highlights: [
            'SMS, e-post eller begge',
            'Varselhub og hendelseskatalog',
            'Ikkesvar@driftpro.no for systemmeldinger',
          ],
        ),
        DriftProFeature(
          title: 'Infoskjerm / kiosk',
          description:
              'Digital infoskjerm for lager og kontor med personvernmodus uten navn på felles skjerm.',
          icon: Icons.tv_outlined,
        ),
        DriftProFeature(
          title: 'Online & tilstedeværelse',
          description:
              'Se hvem som er på jobb, planlegg dekning og få oversikt over teamets tilgjengelighet.',
          icon: Icons.people_alt_outlined,
        ),
      ],
    ),
    DriftProFeatureGroup(
      title: 'Fravær & HR',
      subtitle: 'Ferie, fravær og personaladministrasjon',
      icon: Icons.beach_access_outlined,
      accent: Color(0xFF1565C0),
      features: [
        DriftProFeature(
          title: 'Fravær og ferie',
          description:
              'Komplett fraværsmodul med søknad, godkjenning, saldo og Lovdata-baserte regler.',
          icon: Icons.event_available_outlined,
          highlights: [
            'Ferie, egenmelding, sykt barn, permisjon, sykmelding',
            'Leder-godkjenning og teamoversikt',
            'Dobbel kalender: ferie og fravær',
            'Røde dager og regelhjelp fra Lovdata',
          ],
        ),
        DriftProFeature(
          title: 'Ansatte & avdelinger',
          description:
              'HR-register med profiler, roller, avdelingstilhørighet og organisasjonskart.',
          icon: Icons.groups_outlined,
          highlights: [
            'Superadmin kan redigere ansattprofiler og e-post',
            'Fødselsnummer med automatisk fødselsdato',
            'Brukergodkjenning ved onboarding',
          ],
        ),
        DriftProFeature(
          title: 'Personalmappe',
          description:
              'Digital personalmappe per ansatt med dokumenter, filer og kompetansebevis.',
          icon: Icons.folder_shared_outlined,
        ),
        DriftProFeature(
          title: 'Undersøkelser',
          description:
              'Bygg og send interne undersøkelser — for kultur, HMS og medarbeiderinvolvering.',
          icon: Icons.poll_outlined,
        ),
      ],
    ),
    DriftProFeatureGroup(
      title: 'HMS & kvalitet',
      subtitle: 'Avvik, risiko, sikkerhet og dokumentstyring',
      icon: Icons.health_and_safety_outlined,
      accent: Color(0xFFC62828),
      features: [
        DriftProFeature(
          title: 'Avvik (HMS)',
          description:
              'Rapporter avvik med bilder, GPS, alvorlighetsgrad, tildeling og lederoppfølging.',
          icon: Icons.report_problem_outlined,
          highlights: [
            'Hurtigmaler og mediaopplasting',
            'Statusflyt fra åpen til lukket',
            'Kobling mot risikoanalyse',
          ],
        ),
        DriftProFeature(
          title: 'Risikoanalyse (ROS)',
          description:
              'Strukturerte risikovurderinger med 5×5 matrise, tiltak og sporbar historikk.',
          icon: Icons.grid_on_outlined,
        ),
        DriftProFeature(
          title: 'SJA — Sikker jobbanalyse',
          description:
              'Digitale SJA med maler, farepunkter, PPE og digital signatur.',
          icon: Icons.assignment_turned_in_outlined,
        ),
        DriftProFeature(
          title: 'Vernerunder',
          description:
              'Planlegg og gjennomfør vernerunder med sjekklister, bilder og PDF-arkiv.',
          icon: Icons.fact_check_outlined,
        ),
        DriftProFeature(
          title: 'Maskiner & utstyr',
          description:
              'Utstyrsregister med serviceintervaller, inspeksjoner og dokumentasjon.',
          icon: Icons.construction_outlined,
        ),
        DriftProFeature(
          title: 'Kompetanse & kurs',
          description:
              'Kompetansematrise, kursbevis, utløpsvarsler og dokumentasjon per ansatt.',
          icon: Icons.school_outlined,
        ),
        DriftProFeature(
          title: 'DMS — Dokumentstyring',
          description:
              'Bedriftens dokumenthåndbok med mapper, tilganger, forhåndsvisning og versjoner.',
          icon: Icons.description_outlined,
        ),
        DriftProFeature(
          title: 'Anonym varsling',
          description:
              'Whistleblowing-kanal for sensitive forhold — adskilt fra ordinære avvik.',
          icon: Icons.record_voice_over_outlined,
        ),
      ],
    ),
    DriftProFeatureGroup(
      title: 'Partnere & rutedrift',
      subtitle: 'Transportpartnere, PDF-ruter og operativ planlegging',
      icon: Icons.local_shipping_outlined,
      accent: Color(0xFF6A1B9A),
      features: [
        DriftProFeature(
          title: 'Samarbeidspartnere',
          description:
              'Register over transportpartnere med Brreg, kjøretøy, dokumenter og revisjon.',
          icon: Icons.handshake_outlined,
        ),
        DriftProFeature(
          title: 'Rute-PDF & mass auto',
          description:
              'Importer, tildel og publiser ruter fra PDF — inkl. AUTO MASS og masseopplasting.',
          icon: Icons.picture_as_pdf_outlined,
          highlights: [
            'SAP e-post innboks (ruter@driftpro.no)',
            'MAVI-kode og stowing lane fra PDF',
            'Publiseringskø og master-scheduler',
          ],
        ),
        DriftProFeature(
          title: 'Flåte & rutedashboard',
          description:
              'Operativ oversikt over ruter, kjøretøy, ledig kapasitet og tildeling per dag.',
          icon: Icons.map_outlined,
        ),
        DriftProFeature(
          title: 'Sjåførportal',
          description:
              'Egen portal for sjåfører: ruter, PDF, kvittering og daglig arbeidsflyt.',
          icon: Icons.badge_outlined,
        ),
        DriftProFeature(
          title: 'Eierportal (bil-eier)',
          description:
              'Portal for transportører/eiere: rutehistorikk, dokumenter og økonomisk oversikt.',
          icon: Icons.business_center_outlined,
        ),
        DriftProFeature(
          title: 'SMS til rute-kunder',
          description:
              'Hent kunder fra rute-PDF og send SMS-varsler direkte fra plattformen.',
          icon: Icons.sms_outlined,
        ),
        DriftProFeature(
          title: 'Bilutleie & inspeksjon',
          description:
              'Utleieavtaler, kjøretøyinspeksjon og dokumentasjon knyttet til partner.',
          icon: Icons.car_rental_outlined,
        ),
        DriftProFeature(
          title: 'Felles rutiner & prosedyrer',
          description:
              'Delt dokumentasjon på tvers av partnere — standardiserte prosedyrer.',
          icon: Icons.menu_book_outlined,
        ),
      ],
    ),
    DriftProFeatureGroup(
      title: 'Ruteplanlegging (desktop)',
      subtitle: 'Komplett ruteplanleggingssystem for Mac og PC',
      icon: Icons.alt_route_outlined,
      accent: Color(0xFFEF6C00),
      features: [
        DriftProFeature(
          title: 'DriftPro Dispatch',
          description:
              'Dedikert desktop-app for profesjonell ruteplanlegging — samme database som web.',
          icon: Icons.desktop_windows_outlined,
          status: DriftProFeatureStatus.live,
          highlights: [
            'Ordre- og ruteoptimalisering',
            'Last mile / VRPTW-støtte',
            'Integrert med partner- og rutedata',
          ],
        ),
      ],
    ),
    DriftProFeatureGroup(
      title: 'Plattform & sikkerhet',
      subtitle: 'Infrastruktur, lagring og tilgangsstyring',
      icon: Icons.shield_outlined,
      accent: Color(0xFF37474F),
      features: [
        DriftProFeature(
          title: 'Tilgangskontroll',
          description:
              'Granulære roller: superadmin, admin, leder og ansatt — med modulbasert tilgang.',
          icon: Icons.lock_person_outlined,
        ),
        DriftProFeature(
          title: 'Supabase backend',
          description:
              'Sikker sky-database med Row Level Security, audit og sanntidssynkronisering.',
          icon: Icons.storage_outlined,
        ),
      ],
    ),
    DriftProFeatureGroup(
      title: 'Under utvikling',
      subtitle: 'Kommende moduler i DriftPro-økosystemet',
      icon: Icons.rocket_launch_outlined,
      accent: Color(0xFF00838F),
      features: [
        DriftProFeature(
          title: 'Sjåfør-app (mobil)',
          description:
              'Dedikert mobilapp for sjåfører med ruter, navigasjon, POD og offline-støtte.',
          icon: Icons.phone_android_outlined,
          status: DriftProFeatureStatus.planned,
        ),
        DriftProFeature(
          title: 'Lager- & oversiktsapp',
          description:
              'Operativ lagerapp med oversikt over kapasitet, plukk og daglig produksjon.',
          icon: Icons.warehouse_outlined,
          status: DriftProFeatureStatus.planned,
        ),
        DriftProFeature(
          title: 'Track & sporing',
          description:
              'Sanntidssporing av kjøretøy og leveranser — integrert med ruteplan og kundevarsling.',
          icon: Icons.gps_fixed_outlined,
          status: DriftProFeatureStatus.planned,
        ),
        DriftProFeature(
          title: 'Utvidet telemetri',
          description:
              'Kjøreadferd, temperatur og ETA — koblet til flåte og kundeservice.',
          icon: Icons.sensors_outlined,
          status: DriftProFeatureStatus.beta,
        ),
      ],
    ),
  ];

  static List<DriftProFeature> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final hits = <DriftProFeature>[];
    for (final g in groups) {
      for (final f in g.features) {
        final blob =
            '${f.title} ${f.description} ${f.highlights.join(' ')} ${g.title}'
                .toLowerCase();
        if (blob.contains(q)) hits.add(f);
      }
    }
    return hits;
  }
}
