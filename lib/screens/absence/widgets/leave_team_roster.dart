import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/services/absence/employee_leave_stats.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/leave_usage_colors.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';

enum _RosterSort { snartFerie, fravaer, ferieIgjen, status, navn }

/// Lederoversikt: full status i kortet, uten å åpne den ansatte.
class LeaveTeamRoster extends StatefulWidget {
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

  @override
  State<LeaveTeamRoster> createState() => _LeaveTeamRosterState();
}

class _LeaveTeamRosterState extends State<LeaveTeamRoster> {
  _RosterSort _sort = _RosterSort.snartFerie;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _coversToday(Absence a) {
    if (a.status != AbsenceStatus.godkjent) return false;
    final t = _day(DateTime.now());
    return !t.isBefore(_day(a.startDate)) && !t.isAfter(_day(a.endDate));
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d. MMM', 'nb_NO');
    final today = _day(DateTime.now());
    final rows = <_RosterCard>[];

    for (final person in widget.employees) {
      final abs = widget.absencesFor(person.id);
      final away = abs.where(_coversToday).toList()
        ..sort((a, b) => a.endDate.compareTo(b.endDate));
      final pending = abs.where((a) => a.status == AbsenceStatus.ventende).toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
      final upcoming = abs.where((a) {
        if (a.status != AbsenceStatus.godkjent) return false;
        return _day(a.startDate).isAfter(today);
      }).toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
      final nextFerie = upcoming.cast<Absence?>().firstWhere(
            (a) => a!.type == AbsenceType.ferie,
            orElse: () => null,
          );
      final stats = EmployeeLeaveSnapshot.compute(
        employee: person,
        employeeAbsences: abs,
        quota: widget.quotaFor(person.id),
        company: widget.company,
        referenceDate: DateTime.now(),
      );
      final onLeave = away.isNotEmpty;
      final soonDays = nextFerie == null
          ? null
          : _day(nextFerie.startDate).difference(today).inDays;

      rows.add(_RosterCard(
        person: person,
        away: away.isEmpty ? null : away.first,
        pending: pending.isEmpty ? null : pending.first,
        nextFerie: nextFerie,
        daysUntilFerie: soonDays,
        stats: stats,
        onLeave: onLeave,
        waiting: pending.isNotEmpty,
      ));
    }

    rows.sort((a, b) => _compare(a, b));

    final soon = rows.where((r) {
      final d = r.daysUntilFerie;
      return d != null && d <= 21;
    }).length;
    final awayCount = rows.where((r) => r.onLeave).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    awayCount == 0
                        ? 'Ingen borte i dag'
                        : '$awayCount borte nå',
                    style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    soon == 0
                        ? '${rows.length} ansatte'
                        : '$soon har ferie innen 3 uker',
                    style: DriftProTheme.caption,
                  ),
                ],
              ),
            ),
            _SortMenu(
              value: _sort,
              onChanged: (v) => setState(() => _sort = v),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final row in rows)
          _card(context, row, df),
      ],
    );
  }

  int _compare(_RosterCard a, _RosterCard b) {
    switch (_sort) {
      case _RosterSort.snartFerie:
        final ad = a.daysUntilFerie ?? 9999;
        final bd = b.daysUntilFerie ?? 9999;
        final byDate = ad.compareTo(bd);
        if (byDate != 0) return byDate;
        return a.person.fullName.compareTo(b.person.fullName);
      case _RosterSort.fravaer:
        final byRate = b.stats.absenceRatePercent().compareTo(a.stats.absenceRatePercent());
        if (byRate != 0) return byRate;
        return a.person.fullName.compareTo(b.person.fullName);
      case _RosterSort.ferieIgjen:
        final byLeft = a.stats.ferieRemaining.compareTo(b.stats.ferieRemaining);
        if (byLeft != 0) return byLeft;
        return a.person.fullName.compareTo(b.person.fullName);
      case _RosterSort.status:
        int rank(_RosterCard r) {
          if (r.onLeave) return 0;
          if (r.waiting) return 1;
          if (r.daysUntilFerie != null) return 2;
          return 3;
        }
        final byStatus = rank(a).compareTo(rank(b));
        if (byStatus != 0) return byStatus;
        return a.person.fullName.compareTo(b.person.fullName);
      case _RosterSort.navn:
        return a.person.fullName.compareTo(b.person.fullName);
    }
  }

  Widget _card(BuildContext context, _RosterCard row, DateFormat df) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = _status(row);
    final rate = row.stats.absenceRatePercent();
    final rateColor = LeaveUsageColors.colorFor(
      row.stats.absenceRateLevel(),
      DriftProTheme.primaryGreen,
    );
    final soon = row.daysUntilFerie != null && row.daysUntilFerie! <= 21;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => widget.onOpen(row.person),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: soon
                    ? DriftProTheme.primaryGreen.withValues(alpha: 0.45)
                    : (isDark ? DriftProTheme.dividerDark : const Color(0xFFE3EBE6)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: status.color.withValues(alpha: 0.14),
                      child: Text(
                        row.person.initials,
                        style: TextStyle(
                          color: status.color,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        row.person.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    _pill(status.label, status.color),
                  ],
                ),
                const SizedBox(height: 10),
                _ferieLine(row, df, soon),
                if (row.pending != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Venter: ${row.pending!.type.label} ${df.format(row.pending!.startDate)}–${df.format(row.pending!.endDate)}',
                    style: DriftProTheme.caption.copyWith(
                      color: DriftProTheme.warning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    _metric('Fravær', _percent(rate), rateColor),
                    _metric(
                      'Ferie igjen',
                      '${row.stats.ferieRemaining}/${row.stats.ferieTotal}',
                      DriftProTheme.primaryGreen,
                    ),
                    _metric(
                      'Egenmelding',
                      '${row.stats.egenDaysTotal}/${row.stats.egenMax}',
                      LeaveUsageColors.colorFor(row.stats.egenLevel, DriftProTheme.primaryGreen),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ferieLine(_RosterCard row, DateFormat df, bool soon) {
    final IconData icon;
    final String text;
    final Color color;
    if (row.away?.type == AbsenceType.ferie) {
      icon = Icons.beach_access_outlined;
      text = 'Ferie nå · til ${df.format(row.away!.endDate)}';
      color = DriftProTheme.primaryGreen;
    } else if (row.away != null) {
      icon = Icons.event_busy_outlined;
      text = '${row.away!.type.label} nå · til ${df.format(row.away!.endDate)}';
      color = widget.colorForType?.call(row.away!.type) ?? DriftProTheme.warning;
    } else if (row.nextFerie != null) {
      final d = row.daysUntilFerie!;
      final when = d == 0
          ? 'i dag'
          : d == 1
              ? 'i morgen'
              : 'om $d dager';
      icon = Icons.beach_access_outlined;
      text = 'Ferie $when · ${df.format(row.nextFerie!.startDate)}–${df.format(row.nextFerie!.endDate)}';
      color = soon ? DriftProTheme.primaryGreen : Theme.of(context).colorScheme.onSurfaceVariant;
    } else {
      icon = Icons.event_available_outlined;
      text = 'Ingen planlagt ferie';
      color = Theme.of(context).colorScheme.onSurfaceVariant;
    }

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.25,
              fontWeight: soon || row.onLeave ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  ({String label, Color color}) _status(_RosterCard row) {
    if (row.away != null) {
      return (
        label: row.away!.type.label,
        color: widget.colorForType?.call(row.away!.type) ?? DriftProTheme.primaryGreen,
      );
    }
    if (row.waiting) {
      return (label: 'Venter', color: DriftProTheme.warning);
    }
    if (row.daysUntilFerie != null && row.daysUntilFerie! <= 21) {
      return (label: 'Snart ferie', color: DriftProTheme.primaryGreen);
    }
    return (label: '', color: DriftProTheme.primaryGreen);
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _metric(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: DriftProTheme.caption.copyWith(fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  String _percent(double value) {
    final text = value >= 10
        ? value.round().toString()
        : value.toStringAsFixed(1).replaceAll('.', ',');
    return '$text %';
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.value, required this.onChanged});

  final _RosterSort value;
  final ValueChanged<_RosterSort> onChanged;

  static const _labels = {
    _RosterSort.snartFerie: 'Snart ferie',
    _RosterSort.fravaer: 'Mest fravær',
    _RosterSort.ferieIgjen: 'Minst ferie igjen',
    _RosterSort.status: 'Status',
    _RosterSort.navn: 'Navn',
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_RosterSort>(
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final sort in _RosterSort.values)
          PopupMenuItem(value: sort, child: Text(_labels[sort]!)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE3EBE6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, size: 16, color: DriftProTheme.primaryGreen),
            const SizedBox(width: 6),
            Text(
              _labels[value]!,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _RosterCard {
  const _RosterCard({
    required this.person,
    required this.stats,
    required this.onLeave,
    required this.waiting,
    this.away,
    this.pending,
    this.nextFerie,
    this.daysUntilFerie,
  });

  final UserProfile person;
  final EmployeeLeaveSnapshot stats;
  final bool onLeave;
  final bool waiting;
  final Absence? away;
  final Absence? pending;
  final Absence? nextFerie;
  final int? daysUntilFerie;
}
