import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/absence/employee_leave_stats.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/leave_rules.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';

enum _RosterBucket { borte, venter, jobb }

/// Telefonvennlig teamliste: én rad per ansatt, status med én gang.
class LeaveTeamRoster extends StatelessWidget {
  const LeaveTeamRoster({
    super.key,
    required this.employees,
    required this.absencesFor,
    required this.quotaFor,
    required this.company,
    required this.onOpen,
    this.onAbsenceTap,
    this.colorForType,
  });

  final List<UserProfile> employees;
  final List<Absence> Function(String userId) absencesFor;
  final AbsenceQuota? Function(String userId) quotaFor;
  final CompanyLeaveSettings company;
  final Color Function(AbsenceType type)? colorForType;
  final ValueChanged<UserProfile> onOpen;
  final void Function(Absence absence)? onAbsenceTap;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _coversToday(Absence a) {
    if (a.status != AbsenceStatus.godkjent) return false;
    final t = _day(DateTime.now());
    return !t.isBefore(_day(a.startDate)) && !t.isAfter(_day(a.endDate));
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d. MMM', 'nb_NO');
    final rows = <_RosterRow>[];
    for (final person in employees) {
      final abs = absencesFor(person.id);
      final today = abs.where(_coversToday).toList()
        ..sort((a, b) => a.endDate.compareTo(b.endDate));
      final pending = abs.where((a) => a.status == AbsenceStatus.ventende).toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
      final upcoming = abs.where((a) {
        if (a.status != AbsenceStatus.godkjent) return false;
        return _day(a.startDate).isAfter(_day(DateTime.now()));
      }).toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));

      final stats = EmployeeLeaveSnapshot.compute(
        employee: person,
        employeeAbsences: abs,
        quota: quotaFor(person.id),
        company: company,
        referenceDate: DateTime.now(),
      );

      if (today.isNotEmpty) {
        final a = today.first;
        rows.add(_RosterRow(
          person: person,
          bucket: _RosterBucket.borte,
          title: a.type.label,
          detail: 'til ${df.format(a.endDate)}',
          absence: a,
          color: colorForType?.call(a.type) ?? DriftProTheme.absenceVacation,
        ));
      } else if (pending.isNotEmpty) {
        final a = pending.first;
        rows.add(_RosterRow(
          person: person,
          bucket: _RosterBucket.venter,
          title: 'Venter',
          detail: '${a.type.label} ${df.format(a.startDate)}',
          absence: a,
          color: colorForType?.call(a.type) ?? DriftProTheme.warning,
        ));
      } else {
        final next = upcoming.isEmpty ? null : upcoming.first;
        rows.add(_RosterRow(
          person: person,
          bucket: _RosterBucket.jobb,
          title: 'På jobb',
          detail: next == null
              ? '${stats.ferieRemaining} feriedager igjen'
              : '${next.type.label} fra ${df.format(next.startDate)} · ${stats.ferieRemaining} igjen',
          color: DriftProTheme.primaryGreen,
        ));
      }
    }

    rows.sort((a, b) {
      final order = a.bucket.index.compareTo(b.bucket.index);
      if (order != 0) return order;
      return a.person.fullName.compareTo(b.person.fullName);
    });

    final away = rows.where((r) => r.bucket == _RosterBucket.borte).length;
    final waiting = rows.where((r) => r.bucket == _RosterBucket.venter).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        Text(
          away == 0 && waiting == 0
              ? 'Alle er på jobb'
              : '${rows.length} ansatte · $away borte · $waiting venter',
          style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Trykk en rad for ferie, fravær og saldo.',
          style: DriftProTheme.caption,
        ),
        const SizedBox(height: 12),
        for (final row in rows)
          _tile(
            context,
            row,
            onTap: () {
              if (row.absence != null && onAbsenceTap != null) {
                onAbsenceTap!(row.absence!);
              } else {
                onOpen(row.person);
              }
            },
          ),
      ],
    );
  }

  Widget _tile(BuildContext context, _RosterRow row, {required VoidCallback onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? DriftProTheme.dividerDark : const Color(0xFFE3EBE6),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: row.color.withValues(alpha: 0.14),
                  child: Text(
                    row.person.initials,
                    style: TextStyle(
                      color: row.color,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.person.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DriftProTheme.labelMd.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        row.detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DriftProTheme.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: row.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    row.title,
                    style: TextStyle(
                      color: row.color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RosterRow {
  const _RosterRow({
    required this.person,
    required this.bucket,
    required this.title,
    required this.detail,
    required this.color,
    this.absence,
  });

  final UserProfile person;
  final _RosterBucket bucket;
  final String title;
  final String detail;
  final Color color;
  final Absence? absence;
}
