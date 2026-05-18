/// Truck-kontrollmaler (gaffel vs klem) — lagres i `equipment.truck_checklist_data`.
enum TruckSubtype { fork, clamp, other }

extension TruckSubtypeExtension on TruckSubtype {
  String get label {
    switch (this) {
      case TruckSubtype.fork:
        return 'Gaffeltruck';
      case TruckSubtype.clamp:
        return 'Klemtruck';
      case TruckSubtype.other:
        return 'Annen truck';
    }
  }

  String get dbValue => name;

  static TruckSubtype fromDb(String? v) {
    switch (v) {
      case 'fork':
        return TruckSubtype.fork;
      case 'clamp':
        return TruckSubtype.clamp;
      default:
        return TruckSubtype.other;
    }
  }
}

class TruckChecklistItem {
  final String id;
  final String label;
  final String group;
  final bool critical;

  const TruckChecklistItem({
    required this.id,
    required this.label,
    required this.group,
    this.critical = false,
  });
}

class TruckInspectionTemplates {
  TruckInspectionTemplates._();

  static List<TruckChecklistItem> itemsFor(TruckSubtype subtype) {
    final common = _commonItems;
    switch (subtype) {
      case TruckSubtype.clamp:
        return [...common, ..._clampItems];
      case TruckSubtype.fork:
        return [...common, ..._forkItems];
      case TruckSubtype.other:
        return [...common, ..._forkItems];
    }
  }

  static const _commonItems = [
    TruckChecklistItem(
      id: 'daily_visual',
      label: 'Daglig visuell kontroll utført',
      group: 'Daglig',
      critical: true,
    ),
    TruckChecklistItem(
      id: 'brakes',
      label: 'Bremser — funksjon og respons',
      group: 'Sikkerhet',
      critical: true,
    ),
    TruckChecklistItem(
      id: 'steering',
      label: 'Styring — ingen unormal speling',
      group: 'Sikkerhet',
      critical: true,
    ),
    TruckChecklistItem(
      id: 'horn_lights',
      label: 'Signalhorn, blinklys og arbeidslys',
      group: 'Sikkerhet',
    ),
    TruckChecklistItem(
      id: 'seat_belt',
      label: 'Setebelte og sete i orden',
      group: 'Sikkerhet',
      critical: true,
    ),
    TruckChecklistItem(
      id: 'battery_fluid',
      label: 'Batteri / væskenivå kontrollert',
      group: 'Vedlikehold',
    ),
    TruckChecklistItem(
      id: 'hydraulic_leak',
      label: 'Ingen synlig hydraulikklekkasje',
      group: 'Vedlikehold',
      critical: true,
    ),
    TruckChecklistItem(
      id: 'tires_wheels',
      label: 'Dekk / hjul — skader og slitasje',
      group: 'Vedlikehold',
    ),
    TruckChecklistItem(
      id: 'load_capacity',
      label: 'Lasteskilt / kapasitet lesbar',
      group: 'Dokumentasjon',
    ),
    TruckChecklistItem(
      id: 'operator_cert',
      label: 'Fører har gyldig truckførerbevis',
      group: 'Dokumentasjon',
      critical: true,
    ),
    TruckChecklistItem(
      id: 'service_book',
      label: 'Servicehefte føres og er tilgjengelig',
      group: 'Dokumentasjon',
    ),
  ];

  static const _forkItems = [
    TruckChecklistItem(
      id: 'forks_condition',
      label: 'Gafler — ingen sprekker, bøy eller slitasje',
      group: 'Gaffel',
      critical: true,
    ),
    TruckChecklistItem(
      id: 'fork_lock',
      label: 'Gaffelfeste / lås — sikret',
      group: 'Gaffel',
      critical: true,
    ),
    TruckChecklistItem(
      id: 'mast_chains',
      label: 'Mast og kjettinger — smøring og skader',
      group: 'Gaffel',
    ),
    TruckChecklistItem(
      id: 'forks_level',
      label: 'Gaffelvinkel / nivåfunksjon OK',
      group: 'Gaffel',
    ),
    TruckChecklistItem(
      id: 'load_backrest',
      label: 'Lastbakke / ryggstøtte intakt',
      group: 'Gaffel',
    ),
  ];

  static const _clampItems = [
    TruckChecklistItem(
      id: 'clamp_pads',
      label: 'Klemmeputer — slitasje og feste',
      group: 'Klemme',
      critical: true,
    ),
    TruckChecklistItem(
      id: 'clamp_pressure',
      label: 'Klemtrykk / hydraulikk — jevn funksjon',
      group: 'Klemme',
      critical: true,
    ),
    TruckChecklistItem(
      id: 'clamp_rotation',
      label: 'Rotasjon / sideforskyvning — kontrollert bevegelse',
      group: 'Klemme',
    ),
    TruckChecklistItem(
      id: 'load_stability',
      label: 'Laststabilitet ved klem — testet',
      group: 'Klemme',
      critical: true,
    ),
    TruckChecklistItem(
      id: 'clamp_mast',
      label: 'Mast og kjettinger — smøring og skader',
      group: 'Klemme',
    ),
  ];

  /// Standard neste inspeksjon (dager) etter fullført kontroll.
  static int defaultInspectionIntervalDays(TruckSubtype subtype) {
    switch (subtype) {
      case TruckSubtype.clamp:
        return 7;
      case TruckSubtype.fork:
        return 7;
      case TruckSubtype.other:
        return 14;
    }
  }
}
