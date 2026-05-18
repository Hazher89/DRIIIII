import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';

/// Smart søk på tvers av partner og kjøretøy.
class PartnerSearch {
  PartnerSearch._();

  static String normalize(String input) =>
      input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String digitsOnly(String input) =>
      input.replaceAll(RegExp(r'\D'), '');

  static String compactMavi(String input) {
    final u = input.toUpperCase().replaceAll(RegExp(r'\s'), '');
    final m = RegExp(r'NO_O_M0*(\d{1,5})').firstMatch(u);
    if (m != null) {
      final n = int.tryParse(m.group(1)!);
      if (n != null) return 'NO_O_M${n.toString().padLeft(4, '0')}';
    }
    final simple = RegExp(r'M0*(\d{1,5})').firstMatch(u);
    if (simple != null) {
      final n = int.tryParse(simple.group(1)!);
      if (n != null) return 'NO_O_M${n.toString().padLeft(4, '0')}';
    }
    return u;
  }

  static PartnerSearchHit? match({
    required Partner partner,
    required List<PartnerVehicle> vehicles,
    required String query,
  }) {
    final q = normalize(query);
    if (q.isEmpty) return PartnerSearchHit(partner: partner, vehicles: vehicles);

    final qDigits = digitsOnly(q);
    final qMavi = compactMavi(q);

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
    if (phoneMatch(partner.phone)) reasons.add('Telefon');

    final matchedVehicles = <PartnerVehicle>[];
    for (final v in vehicles) {
      var hit = false;
      if (contains(v.registrationNumber)) {
        reasons.add('Reg.nr ${v.registrationNumber}');
        hit = true;
      }
      final unitNorm = compactMavi(v.unitCode);
      if (qMavi.length >= 3 &&
          (unitNorm.contains(qMavi) ||
              compactMavi(q).contains(unitNorm) ||
              normalize(v.unitCode).contains(q))) {
        reasons.add('MAVI ${v.unitCode}');
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
  }) {
    final q = normalize(query);
    if (q.isEmpty) {
      return partners
          .map(
            (p) => PartnerSearchHit(
              partner: p,
              vehicles: vehiclesByPartnerId[p.id] ?? const [],
            ),
          )
          .toList();
    }

    final out = <PartnerSearchHit>[];
    for (final p in partners) {
      final vehicles = vehiclesByPartnerId[p.id] ?? const [];
      final hit = match(partner: p, vehicles: vehicles, query: query);
      if (hit != null) out.add(hit);
    }
    return out;
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
}
