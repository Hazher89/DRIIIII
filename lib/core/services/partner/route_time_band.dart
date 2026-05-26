import 'route_pdf_text_service.dart';

/// Dag vs kveld for ruter — basert på **starttid** i leveringsvindu (SAP/PDF).
class RouteTimeBand {
  RouteTimeBand._();

  /// Start 06:00–11:30 inkl. = dagrute.
  static const int dayStartMinutes = 6 * 60;
  static const int dayEndMinutes = 11 * 60 + 30;

  static String fromDateTime(DateTime? dt) {
    if (dt == null) return 'dag';
    return fromMinutes(dt.hour * 60 + dt.minute);
  }

  static String fromMinutes(int minutes) {
    if (minutes >= dayStartMinutes && minutes <= dayEndMinutes) return 'dag';
    if (minutes > dayEndMinutes) return 'kveld';
    return 'dag';
  }

  /// Tidligste starttid blant stopp — 08:00–16:00 er dag selv om ett stopp er 16:00–22:00.
  static String inferFromStops(List<RoutePdfCustomer> stops, {DateTime? fallbackStart}) {
    int? earliestStartMin;

    for (final s in stops) {
      final w = s.deliveryWindow;
      if (w == null || w.isEmpty) continue;
      final parts = w.split(RegExp(r'[–\-]'));
      final startMin = _minutes(parts.first.trim());
      if (startMin == null) continue;
      earliestStartMin = earliestStartMin == null
          ? startMin
          : (startMin < earliestStartMin ? startMin : earliestStartMin);
    }

    if (earliestStartMin != null) return fromMinutes(earliestStartMin);
    return fromDateTime(fallbackStart);
  }

  static int? _minutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  static String label(String band) => band == 'kveld' ? 'Kveld' : 'Dag';

  static bool isDay(DateTime? dt) => fromDateTime(dt) == 'dag';
  static bool isEvening(DateTime? dt) => fromDateTime(dt) == 'kveld';
}
