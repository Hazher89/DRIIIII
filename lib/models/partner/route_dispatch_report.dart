import 'route_notify_prefs.dart';

/// Én rad i utsendingsrapport (PDF + SMS/push per rute).
class RouteDispatchReportRow {
  const RouteDispatchReportRow({
    required this.shareId,
    required this.delivery,
    required this.pdfOk,
    required this.storageIsDropbox,
    required this.issues,
    this.title,
    this.driverLabel,
    this.phone,
    this.loadIndex,
    this.loadTotal,
    this.shareDate,
  });

  final String shareId;
  final RouteNotifyDelivery delivery;
  final bool pdfOk;
  final bool storageIsDropbox;
  final List<String> issues;
  final String? title;
  final String? driverLabel;
  final String? phone;
  final int? loadIndex;
  final int? loadTotal;
  final DateTime? shareDate;

  bool get isOk => issues.isEmpty;

  bool get isMultiLoad =>
      loadIndex != null && loadTotal != null && loadTotal! > 1;

  String get loadLabel =>
      isMultiLoad ? 'Last $loadIndex/$loadTotal' : '';

  String get displayTitle {
    final base = (title ?? '').trim();
    if (base.isEmpty) return shareId;
    if (loadLabel.isEmpty) return base;
    return '$base · $loadLabel';
  }

  String get statusLine {
    if (isOk) return 'OK';
    return issues.join(' · ');
  }
}

/// Samlet rapport etter publisering / re-sjekk.
class RouteDispatchReport {
  const RouteDispatchReport({required this.rows});

  final List<RouteDispatchReportRow> rows;

  int get totalCount => rows.length;
  int get failedCount => rows.where((r) => !r.isOk).length;
  int get okCount => totalCount - failedCount;
  bool get allOk => failedCount == 0;

  List<RouteDispatchReportRow> get failedRows =>
      rows.where((r) => !r.isOk).toList();

  String failureListText() {
    if (allOk) return 'Alle $totalCount ruter er levert.';
    final buf = StringBuffer('IKKE LEVERT ($failedCount av $totalCount):\n');
    for (final r in failedRows) {
      buf.writeln(
        '• ${r.displayTitle}'
        '${r.driverLabel != null && r.driverLabel!.isNotEmpty ? ' — ${r.driverLabel}' : ''}'
        ': ${r.statusLine}',
      );
    }
    return buf.toString().trim();
  }
}
