import '../../models/user_profile.dart';
import 'access_keys.dart';
import 'access_normalize.dart';

/// Gruppering av alle DriftPro-tilganger for superadmin-matrise (legacy seksjoner).
class AccessSection {
  final String id;
  final String title;
  final String? subtitle;
  final List<String> keys;

  const AccessSection({
    required this.id,
    required this.title,
    this.subtitle,
    required this.keys,
  });
}

class AccessCatalog {
  AccessCatalog._();

  static const sections = [
    AccessSection(
      id: 'nav',
      title: 'Hovednavigasjon (bunnmeny)',
      subtitle: 'Sider brukeren ser nederst i appen',
      keys: [
        AccessKeys.dashboard,
        AccessKeys.surveys,
        AccessKeys.fravaer,
        AccessKeys.avvik,
        AccessKeys.hms,
        AccessKeys.uniformMonitor,
        AccessKeys.partners,
        AccessKeys.stempling,
        AccessKeys.more,
      ],
    ),
    AccessSection(
      id: 'more',
      title: 'Mer-meny og konto',
      keys: [
        AccessKeys.profil,
        AccessKeys.appInnstillinger,
        AccessKeys.avdelinger,
        AccessKeys.ansatte,
        AccessKeys.personalmappe,
        AccessKeys.undersokelser,
        AccessKeys.whistleblowing,
        AccessKeys.kiosk,
        AccessKeys.samarbeidspartnere,
        AccessKeys.tilgangskontroll,
        AccessKeys.brukergodkjenning,
      ],
    ),
    AccessSection(
      id: 'stempling',
      title: 'Stempling – funksjoner',
      subtitle: 'Krever Stempling i bunnmeny',
      keys: [
        AccessKeys.stemplingAdmin,
        AccessKeys.stemplingMobile,
        AccessKeys.stemplingInnstillinger,
      ],
    ),
    AccessSection(
      id: 'fravaer',
      title: 'Fravær & ferie – funksjoner',
      subtitle: 'Krever modulen Fravær & ferie',
      keys: [
        AccessKeys.fravaerGodkjenn,
        AccessKeys.fravaerRegistrerAndre,
        AccessKeys.ferieAdmin,
      ],
    ),
    AccessSection(
      id: 'avvik',
      title: 'Avvik – funksjoner',
      keys: [
        AccessKeys.avvikGodkjenn,
        AccessKeys.avvikKoordinere,
        AccessKeys.avvikAdmin,
      ],
    ),
    AccessSection(
      id: 'hms',
      title: 'HMS – undermoduler',
      subtitle: 'Krever HMS (hovedmodul) i bunnmeny',
      keys: [
        AccessKeys.hmsRisikovurdering,
        AccessKeys.hmsSja,
        AccessKeys.hmsSikkerhetsrunde,
        AccessKeys.hmsRisikomatrise,
        AccessKeys.hmsUtstyr,
        AccessKeys.hmsUtstyrAdmin,
        AccessKeys.hmsUtstyrService,
        AccessKeys.hmsUtstyrServicehefte,
        AccessKeys.hmsKompetanse,
        AccessKeys.hmsDokumenter,
      ],
    ),
    AccessSection(
      id: 'surveys',
      title: 'Undersøkelser – funksjoner',
      keys: [AccessKeys.surveyBygge, AccessKeys.surveyResultater],
    ),
    AccessSection(
      id: 'partners',
      title: 'Samarbeidspartnere – modul',
      subtitle:
          '«Ruter & planlegging» krever fleet_ruter eller partners_tab_ruter',
      keys: [
        AccessKeys.partnersAdmin,
        AccessKeys.fleetRuter,
        AccessKeys.partnersCreate,
        AccessKeys.partnersDelete,
        AccessKeys.partnersEdit,
        AccessKeys.partnersVehicleRental,
        AccessKeys.partnersVehicleRentalApprove,
      ],
    ),
    AccessSection(
      id: 'partner_tabs',
      title: 'Samarbeidspartnere – faner (bedriftsdetalj)',
      subtitle:
          'Krever tilgang til Samarbeidspartnere-modulen. Skjulte faner kan aldri åpnes.',
      keys: AccessKeys.partnerDetailTabKeys,
    ),
    AccessSection(
      id: 'admin',
      title: 'Administrasjon',
      keys: [AccessKeys.ansatteRediger, AccessKeys.avdelingerRediger],
    ),
    AccessSection(
      id: 'uniform',
      title: 'Uniform-monitor (MAVI)',
      subtitle:
          'Live overvåking av MAVI-logo på bryst og vernesko. Bilder lagres i Dropbox.',
      keys: [AccessKeys.uniformMonitorAdmin],
    ),
    AccessSection(
      id: 'varsler',
      title: 'Varsler & varselinnstillinger',
      subtitle:
          'Varselsenter (Mer-meny), SMS/e-post-oppsett og varselinnstillinger i Samarbeid-SMS',
      keys: [AccessKeys.varsler],
    ),
  ];

  static const varslerSectionId = 'varsler';

  /// Normaliser til flat bool-map (legacy) — for eksisterende kallsteder.
  static Map<String, dynamic> normalize(
    Map<String, dynamic>? raw,
    UserRole role,
  ) =>
      AccessNormalize.toLegacy(raw, role);

  /// Normaliser til v2 area/action JSON (for lagring og ny matrise).
  static Map<String, dynamic> normalizeV2(
    Map<String, dynamic>? raw,
    UserRole role,
  ) =>
      AccessNormalize.toV2(raw, role);

  static int countEnabled(Map<String, dynamic> settings) {
    if (settings['version'] == 2) {
      return AccessSettingsDoc.fromJson(settings).countEnabledActions();
    }
    return AccessKeys.allKeys.where((k) => settings[k] == true).length;
  }
}
