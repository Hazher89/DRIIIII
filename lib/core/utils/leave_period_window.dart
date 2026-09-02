import 'package:intl/intl.dart';

import 'business_days.dart';

/// 12-måneders fraværsperiode forankret på ansettelsesdato (som legacy-systemet).
///
/// [periodEnd] er **siste inkluderende dag** i perioden.
class LeavePeriodWindow {
  final DateTime periodStart;
  final DateTime periodEnd;

  /// True når perioden følger ansettelsesdato; false = kalenderår.
  final bool anchoredToHireDate;

  const LeavePeriodWindow({
    required this.periodStart,
    required this.periodEnd,
    this.anchoredToHireDate = false,
  });

  /// Periode som inneholder [referenceDate] (standard: i dag).
  /// Uten [hireDate] faller vi tilbake til kalenderår.
  static LeavePeriodWindow forReference({
    DateTime? hireDate,
    DateTime? referenceDate,
  }) {
    final ref = BusinessDays.dayOnly(referenceDate ?? DateTime.now());

    if (hireDate == null) {
      return LeavePeriodWindow(
        periodStart: DateTime(ref.year, 1, 1),
        periodEnd: DateTime(ref.year, 12, 31),
        anchoredToHireDate: false,
      );
    }

    final hire = BusinessDays.dayOnly(hireDate);
    var periodStart = _anniversaryOnYear(hire, ref.year);
    if (periodStart.isAfter(ref)) {
      periodStart = _anniversaryOnYear(hire, ref.year - 1);
    }
    // Neste årsjubileum er eksklusivt — lagre siste inkluderende dag.
    final nextAnniversary = _anniversaryOnYear(hire, periodStart.year + 1);
    final periodEnd = nextAnniversary.subtract(const Duration(days: 1));
    return LeavePeriodWindow(
      periodStart: periodStart,
      periodEnd: periodEnd,
      anchoredToHireDate: true,
    );
  }

  static DateTime _anniversaryOnYear(DateTime hire, int year) {
    final lastDay = DateTime(year, hire.month + 1, 0).day;
    return DateTime(year, hire.month, hire.day.clamp(1, lastDay));
  }

  bool contains(DateTime date) {
    final d = BusinessDays.dayOnly(date);
    return !d.isBefore(periodStart) && !d.isAfter(periodEnd);
  }

  String formatRange() {
    final fmt = DateFormat('dd.MM.yyyy');
    return '${fmt.format(periodStart)} – ${fmt.format(periodEnd)}';
  }

  /// Kort forklaring til ledere / ansatte.
  String get basisLabel => anchoredToHireDate
      ? '12 mnd. fra ansettelse'
      : 'Kalenderår ${periodStart.year}';

  String formatRangeWithBasis() => '${formatRange()} · $basisLabel';
}
