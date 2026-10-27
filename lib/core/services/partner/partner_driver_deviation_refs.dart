/// Klassifiserer SAP/MAVI-numre fra rute-PDF for sjåføravvik.
///
/// - **Skjemafelt (auto-fyll):** 39… eller 41… (FU / kundenummer)
/// - **Søkbare bilag:** 21…, 22…, 60… (+ øvrige 2…)
/// - **Søk også:** kundenavn og telefon
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

  /// Nummer som skal stå i skjemaet (39… / 41…).
  static bool isFormFillNumber(String n) =>
      n.startsWith('41') || n.startsWith('39');

  /// Freight unit generelt (4…).
  static bool isFreightUnit(String n) => n.startsWith('4');

  /// Søkbare sales order / bilag: 21…, 22…, 60… (og øvrige 2…).
  static bool isSearchableOrderNumber(String n) =>
      n.startsWith('21') ||
      n.startsWith('22') ||
      n.startsWith('60') ||
      n.startsWith('2');

  /// @Deprecated — bruk [isSearchableOrderNumber].
  static bool isBilagNumber(String n) => isSearchableOrderNumber(n);

  static List<String> formFillNumbersFrom(String? raw) =>
      extractNumbers(raw).where(isFormFillNumber).toList(growable: false);

  static List<String> freightUnitsFrom(String? raw) =>
      extractNumbers(raw).where(isFreightUnit).toList(growable: false);

  static List<String> searchableOrdersFrom(String? raw) =>
      extractNumbers(raw).where(isSearchableOrderNumber).toList(growable: false);

  /// @Deprecated — bruk [searchableOrdersFrom].
  static List<String> bilagNumbersFrom(String? raw) => searchableOrdersFrom(raw);

  /// Auto-fyll til skjemafelt: 41… først, deretter 39…, ellers annen 4….
  static String? primaryFormNumber({
    String? freightRaw,
    String? salesOrder,
    String? manual,
  }) {
    for (final candidate in [manual, freightRaw, salesOrder]) {
      final digits = (candidate ?? '').replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 6 && isFormFillNumber(digits)) return digits;
    }
    final fromFreight = formFillNumbersFrom(freightRaw);
    if (fromFreight.isNotEmpty) {
      final prefer41 = fromFreight.where((n) => n.startsWith('41'));
      if (prefer41.isNotEmpty) return prefer41.first;
      return fromFreight.first;
    }
    // Fallback: hvilken som helst FU (4…)
    return primaryFreightUnit(freightRaw);
  }

  static String? primaryFreightUnit(String? freightRaw) {
    final prefer = formFillNumbersFrom(freightRaw);
    if (prefer.isNotEmpty) {
      final p41 = prefer.where((n) => n.startsWith('41'));
      if (p41.isNotEmpty) return p41.first;
      return prefer.first;
    }
    final list = freightUnitsFrom(freightRaw);
    return list.isEmpty ? null : list.first;
  }

  /// Sales order / bilag for lagring og søk (21/22/60/2…).
  static String? primaryBilag({
    String? salesOrder,
    String? manual,
    String? freightRaw,
  }) {
    for (final candidate in [salesOrder, manual]) {
      final digits = (candidate ?? '').replaceAll(RegExp(r'\D'), '');
      if (digits.isNotEmpty && isSearchableOrderNumber(digits)) return digits;
      final from = searchableOrdersFrom(candidate);
      if (from.isNotEmpty) return from.first;
    }
    final fromFreight = searchableOrdersFrom(freightRaw);
    return fromFreight.isEmpty ? null : fromFreight.first;
  }

  static String freightUnitForStorage(String? freightRaw) {
    final form = primaryFormNumber(freightRaw: freightRaw);
    if (form != null) return form;
    final units = freightUnitsFrom(freightRaw);
    if (units.isNotEmpty) return units.join(', ');
    return freightRaw?.trim() ?? '';
  }

  static String? normalizePhoneDigits(String? phone) {
    if (phone == null) return null;
    var d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return null;
    if (d.startsWith('0047') && d.length >= 12) d = d.substring(4);
    if (d.startsWith('47') && d.length >= 10) d = d.substring(2);
    return d;
  }

  static String customerPickerLabel({
    required String name,
    String? freightRaw,
    String? salesOrder,
    int? sequence,
  }) {
    final form = primaryFormNumber(freightRaw: freightRaw);
    final bilag = primaryBilag(salesOrder: salesOrder, freightRaw: freightRaw);
    final parts = <String>[];
    if (sequence != null) parts.add('#$sequence');
    if (form != null) parts.add(form);
    if (bilag != null && bilag != form) parts.add('Ordre $bilag');
    parts.add(name);
    return parts.join(' · ');
  }

  /// CCC/MAVI-søk: navn, telefon, 21/22/60/39/41/2/4…
  static bool looksLikeDeviationQuery(String query) {
    final q = query.trim();
    if (q.length < 2) return false;
    final digits = q.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 4) {
      return digits.startsWith('21') ||
          digits.startsWith('22') ||
          digits.startsWith('60') ||
          digits.startsWith('39') ||
          digits.startsWith('41') ||
          digits.startsWith('2') ||
          digits.startsWith('4') ||
          digits.length >= 8; // telefon
    }
    return q.replaceAll(RegExp(r'[^a-zA-ZæøåÆØÅäöÄÖüÜ]'), '').length >= 3;
  }

  /// Strengere: bilag/tlf (eller kort kundenavn) — ikke vanlige CCC-spørsmål.
  static bool looksLikeDeviationLookupInput(String query) {
    final q = query.trim();
    if (q.length < 3) return false;
    final digits = q.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 6 &&
        (digits.startsWith('21') ||
            digits.startsWith('22') ||
            digits.startsWith('60') ||
            digits.startsWith('39') ||
            digits.startsWith('41') ||
            digits.startsWith('2') ||
            digits.startsWith('4') ||
            digits.length >= 8)) {
      return true;
    }
    // Kort kundenavn uten spørsmålstegn / setningsord
    if (q.contains('?') || q.contains(' ')) return false;
    final letters = q.replaceAll(RegExp(r'[^a-zA-ZæøåÆØÅäöÄÖüÜ]'), '');
    return letters.length >= 3 && letters.length <= 40 && digits.isEmpty;
  }
}
