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
  final ValueChanged<int>? onYearChanged;

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
    this.onYearChanged,
  });

  @override
  State<LeaveTeamTable> createState() => _LeaveTeamTableState();
}

class _LeaveTeamTableState extends State<LeaveTeamTable> {
  String _search = '';
  _TeamSort _sort = _TeamSort.name;

  AbsenceQuota? _quota(String userId, int year) {
    for (final q in widget.quotas) {
      if (q.userId == userId && q.year == year) return q;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prior = widget.year - 1;
    var list = widget.employees.where((e) {
      if (_search.isEmpty) return true;
      return e.fullName.toLowerCase().contains(_search.toLowerCase());
    }).toList();

    list.sort((a, b) {
      final qa = _quota(a.id, widget.year);
      final qb = _quota(b.id, widget.year);
      switch (_sort) {
        case _TeamSort.name:
          return a.fullName.compareTo(b.fullName);
        case _TeamSort.vacationLeft:
          return (qb?.vacationDaysRemaining ?? 0)
              .compareTo(qa?.vacationDaysRemaining ?? 0);
        case _TeamSort.pending:
          final pa = widget.absences
              .where((x) =>
                  x.userId == a.id && x.status == AbsenceStatus.ventende)
              .length;
          final pb = widget.absences
              .where((x) =>
                  x.userId == b.id && x.status == AbsenceStatus.ventende)
              .length;
          return pb.compareTo(pa);
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onYearChanged != null) ...[
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final y = widget.year - 1 + i;
                final selected = y == widget.year;
                return ChoiceChip(
                  label: Text('$y'),
                  selected: selected,
                  onSelected: (_) => widget.onYearChanged!(y),
                  selectedColor:
                      DriftProTheme.primaryGreen.withValues(alpha: 0.22),
                  labelStyle: TextStyle(
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                    color: selected ? DriftProTheme.primaryGreen : null,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          decoration: InputDecoration(
            hintText: 'Søk etter navn…',
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
        const SizedBox(height: 10),
        Text(
          'Mine ansatte · ${widget.year}',
          style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          'Restferie fra $prior vises når den finnes. Trykk ansatt for detaljer.',
          style: DriftProTheme.caption,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    'Ingen ansatte matcher søket.',
                    style: DriftProTheme.bodySm,
                  ),
                )
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final u = list[i];
                    final q = _quota(u.id, widget.year);
                    final priorQ = _quota(u.id, prior);
                    final priorRest = priorQ?.carryoverEligible(
                          widget.company.maxVacationCarryover,
                        ) ??
                        0;
                    final pending = widget.absences
                        .where((a) =>
                            a.userId == u.id &&
                            a.status == AbsenceStatus.ventende)
                        .length;
                    final total = q?.totalVacationDays;
                    final used = q?.vacationDaysUsed;
                    final remaining = q?.vacationDaysRemaining;
                    final carried = q?.vacationDaysCarriedOver ?? 0;

                    return Material(
                      color: isDark ? DriftProTheme.cardDark : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () => widget.onTapEmployee(u),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDark
                                  ? DriftProTheme.dividerDark
                                  : Colors.grey.shade200,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    child: Text(
                                      u.initials,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          u.fullName,
                                          style: DriftProTheme.labelLg.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        if (u.hireDate == null)
                                          Text(
                                            'mangler ansettelsesdato',
                                            style: DriftProTheme.caption
                                                .copyWith(
                                              color: DriftProTheme.warning,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (widget.canEdit)
                                    IconButton(
                                      tooltip: 'Rediger / overfør',
                                      icon: const Icon(
                                        Icons.sync_outlined,
                                      ),
                                      onPressed: () =>
                                          widget.onEditQuota(u, q),
                                    ),
                                  const Icon(Icons.chevron_right, size: 18),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _metric(
                                      'Feriedager',
                                      total == null ? '—' : '$total',
                                      isDark,
                                    ),
                                  ),
                                  Expanded(
                                    child: _metric(
                                      'Brukt',
                                      used == null ? '—' : '$used',
                                      isDark,
                                    ),
                                  ),
                                  Expanded(
                                    child: _metric(
                                      'Til gode',
                                      remaining == null ? '—' : '$remaining',
                                      isDark,
                                      emphasize: true,
                                    ),
                                  ),
                                ],
                              ),
                              if (priorRest > 0 || carried > 0) ...[
                                const SizedBox(height: 8),
                                Text(
                                  priorRest > 0 && (q == null || carried == 0)
                                      ? 'Restferie $prior: $priorRest d (kan overføres)'
                                      : carried > 0
                                          ? 'Inkl. $carried d overført fra tidligere'
                                          : 'Restferie $prior: $priorRest d',
                                  style: DriftProTheme.caption.copyWith(
                                    color: DriftProTheme.primaryGreen,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                              if (pending > 0) ...[
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: _badge(
                                    '$pending venter',
                                    DriftProTheme.warning,
                                  ),
                                ),
                              ],
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

  Widget _metric(String label, String value, bool isDark, {bool emphasize = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: DriftProTheme.caption),
        const SizedBox(height: 2),
        Text(
          value,
          style: DriftProTheme.labelLg.copyWith(
            fontWeight: FontWeight.w900,
            color: emphasize ? DriftProTheme.primaryGreen : null,
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
