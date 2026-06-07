import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/norwegian_holidays.dart';

/// Viser alle røde dager for året — profesjonell referanse under kalenderen.
class LeavePublicHolidaysPanel extends StatelessWidget {
  final int year;
  final bool initiallyExpanded;

  const LeavePublicHolidaysPanel({
    super.key,
    required this.year,
    this.initiallyExpanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final holidays = NorwegianHolidays.forYear(year);
    final now = DateTime.now();
    final upcoming = holidays
        .where((h) => !h.date.isBefore(DateTime(now.year, now.month, now.day)))
        .length;

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
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.event_busy, color: Colors.red.shade700, size: 22),
          ),
          title: Text(
            'Røde dager $year',
            style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${holidays.length} helligdager · $upcoming gjenstår',
            style: DriftProTheme.caption,
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.15)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.red.shade700),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Røde dager er offentlige helligdager i Norge. '
                      'Ferie og egenmelding telles som kalenderdager — '
                      'planlegg ferie med tanke på helligdager i perioden.',
                      style: DriftProTheme.bodySm.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ..._groupedByMonth(holidays).entries.map((e) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.key,
                      style: DriftProTheme.labelSm.copyWith(
                        fontWeight: FontWeight.w800,
                        color: DriftProTheme.primaryGreen,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...e.value.map((h) => _holidayRow(h, isDark, now)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Map<String, List<NorwegianHoliday>> _groupedByMonth(List<NorwegianHoliday> list) {
    final map = <String, List<NorwegianHoliday>>{};
    for (final h in list) {
      final key = DateFormat('MMMM', 'nb_NO').format(h.date);
      map.putIfAbsent(key, () => []).add(h);
    }
    return map;
  }

  Widget _holidayRow(NorwegianHoliday h, bool isDark, DateTime now) {
    final isPast = h.date.isBefore(DateTime(now.year, now.month, now.day));
    final isToday = DateUtils.isSameDay(h.date, now);
    final df = DateFormat('EEEE d. MMMM', 'nb_NO');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isToday
            ? Colors.red.withValues(alpha: 0.12)
            : (isDark ? DriftProTheme.surfaceDark : Colors.grey.shade50),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isToday
              ? Colors.red.shade400
              : (isDark ? DriftProTheme.dividerDark : Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isPast ? Colors.grey : Colors.red.shade600,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h.name,
                  style: DriftProTheme.labelMd.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: isPast ? TextDecoration.lineThrough : null,
                    color: isPast ? Colors.grey : null,
                  ),
                ),
                Text(
                  df.format(h.date),
                  style: DriftProTheme.caption.copyWith(
                    color: isPast ? Colors.grey : null,
                  ),
                ),
              ],
            ),
          ),
          if (isToday)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'I dag',
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
