import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/absence/absence_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';

class TeamLeaveCalendar extends StatelessWidget {
  final DateTime month;
  final List<Absence> absences;
  final List<UserProfile> employees;
  final String? filterUserId;
  final ValueChanged<DateTime> onMonthChanged;
  final void Function(DateTime date, List<Absence> dayAbsences)? onDayTap;
  final Color Function(AbsenceType) colorForType;

  const TeamLeaveCalendar({
    super.key,
    required this.month,
    required this.absences,
    required this.employees,
    required this.onMonthChanged,
    required this.colorForType,
    this.filterUserId,
    this.onDayTap,
  });

  List<Absence> get _filtered {
    if (filterUserId == null) return absences;
    return absences.where((a) => a.userId == filterUserId).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filtered.where((a) => a.status == AbsenceStatus.godkjent).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => onMonthChanged(
                  DateTime(month.year, month.month - 1),
                ),
              ),
              Text(
                DateFormat('MMMM yyyy', 'nb_NO').format(month),
                style: DriftProTheme.headingSm,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => onMonthChanged(
                  DateTime(month.year, month.month + 1),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: ['Ma', 'Ti', 'On', 'To', 'Fr', 'Lø', 'Sø']
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: DriftProTheme.caption.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white54 : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.95,
            ),
            itemCount: 42,
            itemBuilder: (context, index) {
              final firstDay = DateTime(month.year, month.month, 1);
              final firstWeekday = firstDay.weekday - 1;
              final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
              if (index < firstWeekday || index >= daysInMonth + firstWeekday) {
                return const SizedBox();
              }
              final day = index - firstWeekday + 1;
              final date = DateTime(month.year, month.month, day);
              final dayAbsences = AbsenceService.filterActiveOnDate(filtered, date);
              final isToday = DateUtils.isSameDay(date, DateTime.now());

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onDayTap != null
                      ? () => onDayTap!(date, dayAbsences)
                      : null,
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isToday
                          ? DriftProTheme.primaryGreen.withValues(alpha: 0.15)
                          : (dayAbsences.isNotEmpty
                              ? (isDark ? Colors.white10 : Colors.grey.shade50)
                              : null),
                      borderRadius: BorderRadius.circular(10),
                      border: isToday
                          ? Border.all(color: DriftProTheme.primaryGreen, width: 1.5)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (dayAbsences.isNotEmpty)
                          ...dayAbsences.take(2).map(
                                (a) => Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.symmetric(horizontal: 3),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorForType(a.type).withValues(alpha: 0.85),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      (a.userName ?? '?').split(' ').first,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 7,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                        if (dayAbsences.length > 2)
                          Text(
                            '+${dayAbsences.length - 2}',
                            style: const TextStyle(fontSize: 8),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        _Legend(colorForType: colorForType),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color Function(AbsenceType) colorForType;

  const _Legend({required this.colorForType});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
          ),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: AbsenceType.values.map((t) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colorForType(t),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(t.label, style: const TextStyle(fontSize: 10)),
            ],
          );
        }).toList(),
      ),
    );
  }
}
