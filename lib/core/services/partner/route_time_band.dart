/// Dag vs kveld for ruter — basert på første starttid i PDF.
class RouteTimeBand {
  RouteTimeBand._();

  /// 06:00–11:00 inkl. = dag.
  static const int dayStartMinutes = 6 * 60;
  static const int dayEndMinutes = 11 * 60;

  /// Fra 11:30 = kveld.
  static const int eveningStartMinutes = 11 * 60 + 30;

  static String fromDateTime(DateTime? dt) {
    if (dt == null) return 'dag';
    final m = dt.hour * 60 + dt.minute;
    if (m >= dayStartMinutes && m <= dayEndMinutes) return 'dag';
    if (m >= eveningStartMinutes) return 'kveld';
    return 'dag';
  }

  static String label(String band) => band == 'kveld' ? 'Kveld' : 'Dag';

  static bool isDay(DateTime? dt) => fromDateTime(dt) == 'dag';
  static bool isEvening(DateTime? dt) => fromDateTime(dt) == 'kveld';
}
