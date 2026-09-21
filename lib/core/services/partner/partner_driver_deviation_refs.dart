/// Klassifiserer SAP/MAVI-numre fra rute-PDF.
///
/// - **Freight Unit** (forside): starter typisk med **4…** — ikke CCC-søkenøkkel
/// - **Sales order / bilag** (detaljsider): starter typisk med **2…** — det CCC søker på
class PartnerDriverDeviationRefs {
  PartnerDriverDeviationRefs._();

  static final _digitRun = RegExp(r'\d{6,14}');

  static List<String> extractNumbers(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final m in _digitRun.allMatches(raw)) {
      final n = m.group(0)!;
      if (seen.add(n)) out.add(n);
    }
    return out;
  }

  /// Freight unit / «kundenummer» på forsiden (4…).
  static bool isFreightUnit(String n) => n.startsWith('4');

  /// Bilag / sales order (2…).
  static bool isBilagNumber(String n) => n.startsWith('2');

  static List<String> freightUnitsFrom(String? raw) =>
      extractNumbers(raw).where(isFreightUnit).toList(growable: false);

  static List<String> bilagNumbersFrom(String? raw) =>
      extractNumbers(raw).where(isBilagNumber).toList(growable: false);

  static String? primaryFreightUnit(String? freightRaw) {
    final list = freightUnitsFrom(freightRaw);
    return list.isEmpty ? null : list.first;
  }

  /// Bilag for lagring/søk: eksplisitt salesOrder, ellers manuell, ellers fra råtekst.
  static String? primaryBilag({
    String? salesOrder,
    String? manual,
    String? freightRaw,
  }) {
    for (final candidate in [salesOrder, manual]) {
      final digits = (candidate ?? '').replaceAll(RegExp(r'\D'), '');
      if (digits.isNotEmpty && isBilagNumber(digits)) return digits;
      final from = bilagNumbersFrom(candidate);
      if (from.isNotEmpty) return from.first;
    }
    // Ikke plukk 2… fra freight-feltet hvis det bare er 4… der
    final fromFreight = bilagNumbersFrom(freightRaw);
    return fromFreight.isEmpty ? null : fromFreight.first;
  }

  static String freightUnitForStorage(String? freightRaw) {
    final units = freightUnitsFrom(freightRaw);
    if (units.isNotEmpty) return units.join(', ');
    return freightRaw?.trim() ?? '';
  }

  static String customerPickerLabel({
    required String name,
    String? freightRaw,
    String? salesOrder,
    int? sequence,
  }) {
    final freight = primaryFreightUnit(freightRaw);
    final bilag = primaryBilag(salesOrder: salesOrder, freightRaw: freightRaw);
    final parts = <String>[];
    if (sequence != null) parts.add('#$sequence');
    if (bilag != null) parts.add('Bilag $bilag');
    if (freight != null) parts.add('FU $freight');
    parts.add(name);
    return parts.join(' · ');
  }

  /// True når CCC-søk ser ut som bilag (2…) eller FU (4…).
  static bool looksLikeDeviationQuery(String query) {
    final q = query.trim();
    if (q.length < 2) return false;
    final digits = q.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 4 &&
        (digits.startsWith('2') || digits.startsWith('4'))) {
      return true;
    }
    return RegExp(r'\d{6,}').hasMatch(q);
  }
}
