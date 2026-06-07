import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/absence/absence_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/norwegian_holidays.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';

/// Radvis månedsoversikt — én rad per ansatt, tydelig for ledere.
class EmployeeLeaveTimeline extends StatelessWidget {
  final DateTime month;
  final List<UserProfile> employees;
  final List<Absence> absences;
  final Color Function(AbsenceType) colorForType;
  final bool vacationOnly;
  final Map<String, String> departmentNames;

  const EmployeeLeaveTimeline({
    super.key,
    required this.month,
    required this.employees,
    required this.absences,
    required this.colorForType,
    this.vacationOnly = false,
    this.departmentNames = const {},
  });

  static const _nameWidth = 128.0;
  static const _dayW = 22.0;
  static const _rowH = 40.0;

  int get _daysInMonth => DateUtils.getDaysInMonth(month.year, month.month);

  List<Absence> _forUser(String userId) {
    return absences.where((a) {
      if (a.userId != userId) return false;
      if (a.status == AbsenceStatus.avvist) return false;
      if (vacationOnly && a.type != AbsenceType.ferie) return false;
      if (!vacationOnly && a.type == AbsenceType.ferie) return false;
      return true;
    }).toList();
  }

  bool _activeOnDay(Absence a, DateTime date) {
    return AbsenceService.filterActiveOnDate([a], date).isNotEmpty;
  }

  String _title(int employeeCount) {
    final kind = vacationOnly ? 'Ferie' : 'Fravær';
    if (employeeCount == 1) {
      return '$kind — ${employees.first.fullName}';
    }
    return '$kind — $employeeCount ansatte';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (employees.isEmpty) {
      return _emptyCard(isDark, 'Ingen ansatte å vise.');
    }

    final sorted = [...employees]..sort((a, b) => a.fullName.compareTo(b.fullName));

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(
                  vacationOnly ? Icons.beach_access : Icons.event_busy,
                  size: 18,
                  color: vacationOnly
                      ? DriftProTheme.absenceVacation
                      : DriftProTheme.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _title(sorted.length),
                    style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  DateFormat('MMMM yyyy', 'nb_NO').format(month),
                  style: DriftProTheme.caption,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _nameWidth + _daysInMonth * _dayW + 8,
              child: Column(
                children: [
                  _dayHeader(isDark),
                  ...sorted.map((e) => _employeeRow(e, isDark)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _legendDot(
                  vacationOnly
                      ? DriftProTheme.absenceVacation
                      : DriftProTheme.absenceSickSelf,
                  'Godkjent',
                ),
                _legendDot(Colors.orange.shade400, 'Venter', dashed: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayHeader(bool isDark) {
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          SizedBox(
            width: _nameWidth,
            child: Text(
              'Ansatt',
              style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          ...List.generate(_daysInMonth, (i) {
            final d = i + 1;
            final date = DateTime(month.year, month.month, d);
            final isWeekend = date.weekday >= 6;
            final isToday = DateUtils.isSameDay(date, DateTime.now());
            final isRed = NorwegianHolidays.isRedDay(date);
            return SizedBox(
              width: _dayW,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isRed)
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 1),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Text(
                    '$d',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                      color: isRed
                          ? Colors.red.shade800
                          : (isToday
                              ? DriftProTheme.primaryGreen
                              : (isWeekend
                                  ? (isDark ? Colors.white38 : Colors.grey.shade400)
                                  : (isDark ? Colors.white70 : Colors.black54))),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _employeeRow(UserProfile user, bool isDark) {
    final userAbsences = _forUser(user.id);
    final dept = user.departmentId != null
        ? departmentNames[user.departmentId!]
        : null;

    return Container(
      height: _rowH,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _nameWidth,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DriftProTheme.labelSm.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (dept != null)
                    Text(
                      dept,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DriftProTheme.caption.copyWith(fontSize: 9),
                    ),
                ],
              ),
            ),
          ),
          ...List.generate(_daysInMonth, (i) {
            final date = DateTime(month.year, month.month, i + 1);
            final dayItems = userAbsences.where((a) => _activeOnDay(a, date)).toList();
            if (dayItems.isEmpty) {
              return SizedBox(width: _dayW, height: _rowH);
            }
            final primary = dayItems.first;
            final pending = primary.status == AbsenceStatus.ventende;
            final color = colorForType(primary.type);
            return SizedBox(
              width: _dayW,
              height: _rowH,
              child: Center(
                child: Container(
                  width: _dayW - 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: pending ? 0.35 : 0.85),
                    borderRadius: BorderRadius.circular(4),
                    border: pending
                        ? Border.all(color: Colors.orange.shade600, width: 1.2)
                        : null,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label, {bool dashed = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 10,
          decoration: BoxDecoration(
            color: dashed ? color.withValues(alpha: 0.35) : color.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(3),
            border: dashed ? Border.all(color: Colors.orange.shade600) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: DriftProTheme.caption),
      ],
    );
  }

  Widget _emptyCard(bool isDark, String msg) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(msg, textAlign: TextAlign.center, style: DriftProTheme.bodySm),
      ),
    );
  }
}
