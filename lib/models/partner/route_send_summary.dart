import '../../core/services/partner/mavi_unit_codes.dart';
import 'partner_route_dispatch_history.dart';
import 'route_dispatch_report.dart';

/// Én sjåfør-linje i send-rapport («M02 har fått rute med 2 last»).
class RouteSendDriverLine {
  const RouteSendDriverLine({
    required this.maviCode,
    required this.routeCount,
    this.driverName,
    this.partnerName,
  });

  final String maviCode;
  final int routeCount;
  final String? driverName;
  final String? partnerName;

  String get shortMavi {
    final c = maviCode.trim();
    if (c.isEmpty) return '?';
    return MaviUnitCodes.compactLabel(c);
  }

  /// Kort, lesbar linje til rapport.
  String get summaryLine {
    final code = shortMavi;
    if (routeCount <= 1) return '$code har fått rute';
    return '$code har fått rute med $routeCount last';
  }

  String get detailLine {
    final name = (driverName ?? partnerName ?? '').trim();
    if (name.isEmpty) return summaryLine;
    return '$summaryLine · $name';
  }
}

/// Samlet utsendingsrapport for én batch / én dag.
class RouteSendSummary {
  const RouteSendSummary({
    required this.drivers,
    required this.routeCount,
    this.sentAt,
    this.routeDate,
  });

  final List<RouteSendDriverLine> drivers;
  final int routeCount;
  final DateTime? sentAt;
  final DateTime? routeDate;

  int get driverCount => drivers.length;

  String get headline {
    if (routeCount <= 0) return 'Ingen ruter sendt';
    if (driverCount <= 0) return '$routeCount rute(r) sendt';
    return '$routeCount rute(r) sendt til $driverCount sjåfør(er)';
  }

  static RouteSendSummary fromDispatchReport(
    RouteDispatchReport report, {
    DateTime? sentAt,
  }) {
    final byKey = <String, _Acc>{};
    DateTime? routeDate;
    for (final row in report.rows) {
      routeDate ??= row.shareDate;
      final rawLabel = (row.driverLabel ?? '').trim();
      final mavi = _extractMavi(rawLabel) ??
          _extractMavi(row.title) ??
          rawLabel.split(RegExp(r'\s*[—\-·]\s*')).first.trim();
      final key = MaviUnitCodes.normalize(
        mavi.isEmpty ? row.shareId : mavi,
      );
      final name = _extractName(rawLabel);
      final acc = byKey.putIfAbsent(
        key.isEmpty ? row.shareId : key,
        () => _Acc(mavi: key.isEmpty ? (mavi.isEmpty ? '?' : mavi) : key),
      );
      acc.count++;
      if (name != null && name.isNotEmpty) acc.name ??= name;
    }
    final drivers = byKey.values
        .map(
          (a) => RouteSendDriverLine(
            maviCode: a.mavi,
            routeCount: a.count,
            driverName: a.name,
          ),
        )
        .toList()
      ..sort((a, b) => a.shortMavi.compareTo(b.shortMavi));
    return RouteSendSummary(
      drivers: drivers,
      routeCount: report.totalCount,
      sentAt: sentAt ?? DateTime.now(),
      routeDate: routeDate,
    );
  }

  /// Bygg rapport fra lagret rutehistorikk (én dag).
  static RouteSendSummary fromHistoryRows(
    List<PartnerRouteDispatchHistoryRow> rows, {
    DateTime? routeDate,
  }) {
    final sent = rows
        .where(
          (r) =>
              r.dispatchStatus == 'sent' || r.dispatchStatus == 'registered',
        )
        .toList();
    final byKey = <String, _Acc>{};
    DateTime? latestSent;
    for (final r in sent) {
      if (r.sentAt != null &&
          (latestSent == null || r.sentAt!.isAfter(latestSent))) {
        latestSent = r.sentAt;
      }
      final code = (r.unitCode ?? '').trim();
      final key = MaviUnitCodes.normalize(
        code.isEmpty ? r.shareId : code,
      );
      final acc = byKey.putIfAbsent(
        key.isEmpty ? r.shareId : key,
        () => _Acc(mavi: key.isEmpty ? (code.isEmpty ? '?' : code) : key),
      );
      acc.count++;
      final name = (r.partnerName ?? '').trim();
      if (name.isNotEmpty) acc.name ??= name;
    }
    final drivers = byKey.values
        .map(
          (a) => RouteSendDriverLine(
            maviCode: a.mavi,
            routeCount: a.count,
            partnerName: a.name,
          ),
        )
        .toList()
      ..sort((a, b) => a.shortMavi.compareTo(b.shortMavi));
    return RouteSendSummary(
      drivers: drivers,
      routeCount: sent.length,
      sentAt: latestSent,
      routeDate: routeDate ?? (sent.isEmpty ? null : sent.first.shareDate),
    );
  }

  static String? _extractMavi(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final m = RegExp(
      r'(NO_O_M0*[A-Z0-9]+|M0*\d{1,5}|M\d{1,5})',
      caseSensitive: false,
    ).firstMatch(raw);
    return m?.group(1);
  }

  static String? _extractName(String raw) {
    final parts = raw.split(RegExp(r'\s*[—\-·]\s*'));
    if (parts.length < 2) return null;
    final name = parts.sublist(1).join(' — ').trim();
    return name.isEmpty ? null : name;
  }
}

class _Acc {
  _Acc({required this.mavi});
  final String mavi;
  int count = 0;
  String? name;
}
