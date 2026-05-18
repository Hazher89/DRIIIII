import 'package:flutter/material.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';

class LeaveTeamTable extends StatefulWidget {
  final List<UserProfile> employees;
  final List<AbsenceQuota> quotas;
  final List<Absence> absences;
  final CompanyLeaveSettings company;
  final int year;
  final bool canEdit;
  final void Function(UserProfile user, AbsenceQuota? quota) onEditQuota;
  final void Function(UserProfile user) onTapEmployee;

  const LeaveTeamTable({
    super.key,
    required this.employees,
    required this.quotas,
    required this.absences,
    required this.company,
    required this.year,
    required this.canEdit,
    required this.onEditQuota,
    required this.onTapEmployee,
  });

  @override
  State<LeaveTeamTable> createState() => _LeaveTeamTableState();
}

class _LeaveTeamTableState extends State<LeaveTeamTable> {
  String _search = '';
  _TeamSort _sort = _TeamSort.name;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final quotaByUser = {for (final q in widget.quotas) q.userId: q};
    var list = widget.employees.where((e) {
      if (_search.isEmpty) return true;
      return e.fullName.toLowerCase().contains(_search.toLowerCase());
    }).toList();

    list.sort((a, b) {
      final qa = quotaByUser[a.id];
      final qb = quotaByUser[b.id];
      switch (_sort) {
        case _TeamSort.name:
          return a.fullName.compareTo(b.fullName);
        case _TeamSort.vacationLeft:
          return (qb?.vacationDaysRemaining ?? 0)
              .compareTo(qa?.vacationDaysRemaining ?? 0);
        case _TeamSort.pending:
          final pa = widget.absences
              .where((x) => x.userId == a.id && x.status == AbsenceStatus.ventende)
              .length;
          final pb = widget.absences
              .where((x) => x.userId == b.id && x.status == AbsenceStatus.ventende)
              .length;
          return pb.compareTo(pa);
      }
    });

    return Column(
      children: [
        TextField(
          decoration: InputDecoration(
            hintText: 'Søk ansatt…',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _sortChip('Navn', _TeamSort.name),
              _sortChip('Ferie igjen', _TeamSort.vacationLeft),
              _sortChip('Ventende', _TeamSort.pending),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text('Ingen ansatte matcher søket.', style: DriftProTheme.bodySm))
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final u = list[i];
                    final q = quotaByUser[u.id];
                    final pending = widget.absences
                        .where((a) =>
                            a.userId == u.id && a.status == AbsenceStatus.ventende)
                        .length;
                    final onVacation = widget.absences.any((a) {
                      if (a.userId != u.id || a.type != AbsenceType.ferie) return false;
                      if (a.status != AbsenceStatus.godkjent) return false;
                      final now = DateTime.now();
                      return !now.isBefore(a.startDate) && !now.isAfter(a.endDate);
                    });
                    final remaining = q?.vacationDaysRemaining;
                    final carry = q?.carryoverEligible(widget.company.maxVacationCarryover);

                    return Material(
                      color: isDark ? DriftProTheme.cardDark : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () => widget.onTapEmployee(u),
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              CircleAvatar(
                                child: Text(u.initials, style: const TextStyle(fontSize: 12)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(u.fullName, style: DriftProTheme.labelLg),
                                    const SizedBox(height: 4),
                                    Text(
                                      remaining != null
                                          ? 'Ferie igjen: $remaining · Overførbart: ${carry ?? 0} · Ventende: $pending'
                                          : 'Ingen saldo for ${widget.year} — trykk for å opprette',
                                      style: DriftProTheme.caption,
                                    ),
                                  ],
                                ),
                              ),
                              if (onVacation)
                                _badge('På ferie', DriftProTheme.absenceVacation),
                              if (pending > 0)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: _badge('$pending venter', DriftProTheme.warning),
                                ),
                              if (widget.canEdit)
                                IconButton(
                                  icon: const Icon(Icons.edit_calendar_outlined),
                                  onPressed: () => widget.onEditQuota(u, q),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _sortChip(String label, _TeamSort sort) {
    final selected = _sort == sort;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _sort = sort),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}

enum _TeamSort { name, vacationLeft, pending }
