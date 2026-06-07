import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/absence/absence_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/norwegian_holidays.dart';
import '../../../models/absence.dart';

/// Månedsoversikt: hvem er borte, hvor mange dager, status.
class LeaveCalendarMonthDigest extends StatelessWidget {
  final DateTime month;
  final List<Absence> absences;
  final Color Function(AbsenceType) colorForType;
  final bool vacationOnly;

  /// Når false vises kun sammendrag (antall) — ingen liste nedover.
  final bool showEntryList;

  const LeaveCalendarMonthDigest({
    super.key,
    required this.month,
    required this.absences,
    required this.colorForType,
    required this.vacationOnly,
    this.showEntryList = true,
  });

  List<Absence> get _relevant {
    return absences.where((a) {
      if (a.status == AbsenceStatus.avvist) return false;
      if (vacationOnly && a.type != AbsenceType.ferie) return false;
      if (!vacationOnly && a.type == AbsenceType.ferie) return false;
      final mStart = DateTime(month.year, month.month, 1);
      final mEnd = DateTime(month.year, month.month + 1, 0);
      return !(a.endDate.isBefore(mStart) || a.startDate.isAfter(mEnd));
    }).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final list = _relevant;
    final redDays = NorwegianHolidays.forMonth(month.year, month.month).length;
    final approved = list.where((a) => a.status == AbsenceStatus.godkjent).length;
    final pending = list.where((a) => a.status == AbsenceStatus.ventende).length;
    final uniquePeople = list.map((a) => a.userId).toSet().length;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  vacationOnly ? Icons.beach_access : Icons.people_outline,
                  color: vacationOnly
                      ? DriftProTheme.absenceVacation
                      : DriftProTheme.warning,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Månedsoversikt · ${DateFormat('MMMM yyyy', 'nb_NO').format(month)}',
                    style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill('$uniquePeople ansatte', DriftProTheme.primaryGreen),
                _pill('$approved godkjent', DriftProTheme.success),
                if (pending > 0) _pill('$pending venter', DriftProTheme.warning),
                _pill('$redDays røde dager', Colors.red.shade700),
              ],
            ),
            if (list.isEmpty) ...[
              const SizedBox(height: 14),
              Text(
                vacationOnly
                    ? 'Ingen ferie registrert denne måneden.'
                    : 'Ingen fravær registrert denne måneden.',
                style: DriftProTheme.bodySm,
              ),
            ] else if (!showEntryList) ...[
              const SizedBox(height: 10),
              Text(
                '${list.length} ${vacationOnly ? 'ferieperioder' : 'fraværsperioder'} i måneden. '
                'Velg ansatt i listen over for detaljer.',
                style: DriftProTheme.caption.copyWith(
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                ),
              ),
            ] else ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ...list.take(12).map((a) => _row(a, isDark)),
              if (list.length > 12)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '+ ${list.length - 12} flere i perioden',
                    style: DriftProTheme.caption,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _row(Absence a, bool isDark) {
    final color = colorForType(a.type);
    final days = a.totalDays ??
        AbsenceService.dayCount(a.startDate, a.endDate);
    final df = DateFormat('d. MMM', 'nb_NO');
    final statusColor = a.status == AbsenceStatus.godkjent
        ? DriftProTheme.success
        : DriftProTheme.warning;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.userName ?? 'Ansatt',
                  style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${a.type.label} · ${df.format(a.startDate)} – ${df.format(a.endDate)} · $days d.',
                  style: DriftProTheme.caption,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              a.status.label,
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
