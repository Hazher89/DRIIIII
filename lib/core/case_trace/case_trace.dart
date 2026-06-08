/// Permanente sporings-ID-er for avvik/HMS og Bot/Trekk.
abstract final class CaseTrace {
  CaseTrace._();

  /// Kort sporingskode fra UUID (8 tegn) — unik per sak, beholdes ved sletting.
  static String codeFromId(String id) {
    final compact = id.replaceAll('-', '').toUpperCase();
    return compact.length <= 8 ? compact : compact.substring(0, 8);
  }

  static bool matchesQuery({
    required String query,
    String? traceRef,
    String? caseNumber,
    String? id,
    String? logiqrmaCaseNumber,
    String? voucherNumber,
    String? title,
    String? partnerName,
    int? ticketNumber,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;

    final qCompact = q.replaceAll('-', '').replaceAll('#', '');
    final idCode = id == null ? '' : codeFromId(id).toLowerCase();

    bool hit(String? value) =>
        value != null && value.trim().isNotEmpty && value.toLowerCase().contains(q);

    if (hit(traceRef) || hit(caseNumber) || hit(title) || hit(partnerName)) {
      return true;
    }
    if (hit(logiqrmaCaseNumber) || hit(voucherNumber)) return true;
    if (id != null && id.toLowerCase() == q) return true;
    if (idCode == qCompact) return true;
    if (ticketNumber != null && ticketNumber.toString().contains(qCompact)) {
      return true;
    }
    return false;
  }
}
