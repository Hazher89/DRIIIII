import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import 'mavi_unit_codes.dart';

/// Smart søk på tvers av partner og kjøretøy (navn, org.nr, MAVI, reg.nr, telefon).
class PartnerSearch {
  PartnerSearch._();

  static String normalize(String input) =>
      input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String digitsOnly(String input) =>
      input.replaceAll(RegExp(r'\D'), '');

  /// Normaliser MAVI-søk: M68 / M0068 / NO_O_M0068 → samme kanoniske form.
  static String compactMavi(String input) {
    final n = MaviUnitCodes.normalize(input);
    if (n.startsWith('NO_O_M')) return n;
    return input.toUpperCase().replaceAll(RegExp(r'\s'), '');
  }

  static bool looksLikeMaviQuery(String query) {
    final u = query.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');
    if (u.isEmpty) return false;
    return RegExp(r'^(NO_O_)?M0*\d{1,5}$').hasMatch(u) ||
        RegExp(r'^\d{1,5}$').hasMatch(u);
  }

  static bool maviCodesMatch(String query, String unitCode) {
    if (unitCode.trim().isEmpty) return false;
    if (MaviUnitCodes.isRegistrationOnlyUnit(unitCode)) return false;

    final qNorm = compactMavi(query);
    final vNorm = compactMavi(unitCode);
    if (qNorm.isEmpty || vNorm.isEmpty) return false;

    if (qNorm == vNorm) return true;
    if (vNorm.contains(qNorm) || qNorm.contains(vNorm)) return true;

    final qLabel = MaviUnitCodes.compactLabel(query).toLowerCase();
    final vLabel = MaviUnitCodes.compactLabel(unitCode).toLowerCase();
    if (qLabel.isNotEmpty && vLabel.isNotEmpty && qLabel == vLabel) {
      return true;
    }

    // «68» / «0068» mot M0068 når søket ser ut som MAVI-nummer.
    if (looksLikeMaviQuery(query)) {
      final qDigits = digitsOnly(query);
      final vDigits = digitsOnly(vNorm);
      if (qDigits.isNotEmpty &&
          vDigits.isNotEmpty &&
          (vDigits == qDigits.padLeft(vDigits.length, '0') ||
              vDigits.endsWith(qDigits) ||
              int.tryParse(qDigits) == int.tryParse(vDigits))) {
        return true;
      }
    }

    return normalize(unitCode).contains(normalize(query));
  }

  static PartnerSearchHit? match({
    required Partner partner,
    required List<PartnerVehicle> vehicles,
    required String query,
  }) {
    final q = normalize(query);
    if (q.isEmpty) return PartnerSearchHit(partner: partner, vehicles: vehicles);

    final qDigits = digitsOnly(q);

    bool contains(String? field) {
      if (field == null || field.isEmpty) return false;
      return normalize(field).contains(q);
    }

    bool phoneMatch(String? phone) {
      if (phone == null || qDigits.length < 3) return false;
      final p = digitsOnly(phone);
      return p.contains(qDigits) || qDigits.contains(p);
    }

    final reasons = <String>[];

    if (contains(partner.name)) reasons.add('Bedriftsnavn');
    if (contains(partner.tradeName)) reasons.add('Handelsnavn');
    if (contains(partner.ownerName)) reasons.add('Kontaktperson');
    if (contains(partner.orgNumber)) reasons.add('Org.nr');
    if (contains(partner.email)) reasons.add('E-post');
    if (contains(partner.caseCode)) reasons.add('Sakskode');
    if (phoneMatch(partner.phone)) reasons.add('Telefon');

    final matchedVehicles = <PartnerVehicle>[];
    for (final v in vehicles) {
      var hit = false;
      if (contains(v.registrationNumber)) {
        reasons.add('Reg.nr ${v.registrationNumber}');
        hit = true;
      }
      if (maviCodesMatch(query, v.unitCode)) {
        reasons.add('MAVI ${MaviUnitCodes.compactLabel(v.unitCode)}');
        hit = true;
      }
      if (contains(v.driverName)) {
        reasons.add('Sjåfør ${v.driverName}');
        hit = true;
      }
      if (phoneMatch(v.phone)) {
        reasons.add('Kjøretøy-telefon');
        hit = true;
      }
      if (hit) matchedVehicles.add(v);
    }

    if (reasons.isEmpty) return null;

    return PartnerSearchHit(
      partner: partner,
      vehicles: vehicles,
      matchedVehicles: matchedVehicles.isNotEmpty ? matchedVehicles : vehicles,
      matchReasons: reasons.toSet().toList(),
    );
  }

  static List<PartnerSearchHit> filterAll({
    required List<Partner> partners,
    required Map<String, List<PartnerVehicle>> vehiclesByPartnerId,
    required String query,
    bool activeOnly = false,
  }) {
    final source =
        activeOnly ? partners.where((p) => p.isActive) : partners;
    final q = normalize(query);
    if (q.isEmpty) {
      return source
          .map(
            (p) => PartnerSearchHit(
              partner: p,
              vehicles: vehiclesByPartnerId[p.id] ?? const [],
            ),
          )
          .toList();
    }

    final out = <PartnerSearchHit>[];
    for (final p in source) {
      final vehicles = vehiclesByPartnerId[p.id] ?? const [];
      final hit = match(partner: p, vehicles: vehicles, query: query);
      if (hit != null) out.add(hit);
    }
    return out;
  }

  /// True hvis [haystack]-felter eller MAVI-koder treffer [query].
  static bool textMatches({
    required String query,
    required Iterable<String?> fields,
    Iterable<String?> unitCodes = const [],
  }) {
    final q = normalize(query);
    if (q.isEmpty) return true;
    for (final f in fields) {
      if (f != null && f.isNotEmpty && normalize(f).contains(q)) return true;
    }
    for (final code in unitCodes) {
      if (code != null && maviCodesMatch(query, code)) return true;
    }
    return false;
  }
}

class PartnerSearchHit {
  final Partner partner;
  final List<PartnerVehicle> vehicles;
  final List<PartnerVehicle> matchedVehicles;
  final List<String> matchReasons;

  PartnerSearchHit({
    required this.partner,
    required this.vehicles,
    List<PartnerVehicle>? matchedVehicles,
    this.matchReasons = const [],
  }) : matchedVehicles = matchedVehicles ?? vehicles;

  List<String> get maviCodes =>
      vehicles.map((v) => v.unitCode).toList()..sort();

  String get primaryMatchHint {
    if (matchReasons.isEmpty) return '';
    final mavi = matchReasons.where((r) => r.startsWith('MAVI ')).toList();
    if (mavi.isNotEmpty) return mavi.first;
    return matchReasons.first;
  }
}
