import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/absence/department_leave_conflict_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';
import 'department_leave_tip_card.dart';

enum _StatusFilter { alle, ventende, godkjent, avvist }

enum _TypeFilter { alle, ferie, fravaer }

/// Full teamoversikt for ledere — filter, søk og avdelingsoverlapp.
class LeaveTeamOverviewTab extends StatefulWidget {
  final List<Absence> absences;
  final Map<String, List<DepartmentLeaveOverlap>> overlapsByAbsenceId;
  final Map<String, String> departmentNames;
  final Color Function(AbsenceType) colorForType;
  final IconData Function(AbsenceType) iconForType;
  final int Function(Absence) daysFor;
  final void Function(Absence absence)? onApprove;
  final void Function(Absence absence)? onReject;
  final Future<void> Function() onRefresh;

  const LeaveTeamOverviewTab({
    super.key,
    required this.absences,
    required this.overlapsByAbsenceId,
    required this.departmentNames,
    required this.colorForType,
    required this.iconForType,
    required this.daysFor,
    required this.onRefresh,
    this.onApprove,
    this.onReject,
  });

  @override
  State<LeaveTeamOverviewTab> createState() => _LeaveTeamOverviewTabState();
}

class _LeaveTeamOverviewTabState extends State<LeaveTeamOverviewTab> {
  final _searchCtrl = TextEditingController();
  _StatusFilter _status = _StatusFilter.alle;
  _TypeFilter _type = _TypeFilter.alle;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Absence> get _filtered {
    var list = [...widget.absences];
    list.sort((a, b) => b.startDate.compareTo(a.startDate));

    list = list.where((a) {
      switch (_status) {
        case _StatusFilter.alle:
          break;
        case _StatusFilter.ventende:
          if (a.status != AbsenceStatus.ventende) return false;
        case _StatusFilter.godkjent:
          if (a.status != AbsenceStatus.godkjent) return false;
        case _StatusFilter.avvist:
          if (a.status != AbsenceStatus.avvist) return false;
      }
      switch (_type) {
        case _TypeFilter.alle:
          break;
        case _TypeFilter.ferie:
          if (a.type != AbsenceType.ferie) return false;
        case _TypeFilter.fravaer:
          if (a.type == AbsenceType.ferie) return false;
      }
      if (_search.isNotEmpty) {
        final name = (a.userName ?? '').toLowerCase();
        if (!name.contains(_search)) return false;
      }
      return true;
    }).toList();

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final list = _filtered;
    final pending = widget.absences.where((a) => a.status == AbsenceStatus.ventende).length;
    final withOverlap = widget.absences.where((a) {
      final o = widget.overlapsByAbsenceId[a.id] ?? [];
      return o.isNotEmpty && a.status == AbsenceStatus.ventende;
    }).length;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _summaryBanner(isDark, pending, withOverlap, list.length),
          const SizedBox(height: 14),
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Søk ansatt…',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip('Alle status', _status == _StatusFilter.alle, () {
                  setState(() => _status = _StatusFilter.alle);
                }),
                _chip('Ventende', _status == _StatusFilter.ventende, () {
                  setState(() => _status = _StatusFilter.ventende);
                }),
                _chip('Godkjent', _status == _StatusFilter.godkjent, () {
                  setState(() => _status = _StatusFilter.godkjent);
                }),
                _chip('Avvist', _status == _StatusFilter.avvist, () {
                  setState(() => _status = _StatusFilter.avvist);
                }),
                const SizedBox(width: 8),
                _chip('Alle typer', _type == _TypeFilter.alle, () {
                  setState(() => _type = _TypeFilter.alle);
                }),
                _chip('Ferie', _type == _TypeFilter.ferie, () {
                  setState(() => _type = _TypeFilter.ferie);
                }),
                _chip('Fravær', _type == _TypeFilter.fravaer, () {
                  setState(() => _type = _TypeFilter.fravaer);
                }),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text('Ingen treff', style: DriftProTheme.headingSm),
                  const SizedBox(height: 4),
                  Text(
                    'Prøv et annet filter eller søkeord.',
                    style: DriftProTheme.bodySm,
                  ),
                ],
              ),
            )
          else
            ...list.map((a) => _requestCard(a, isDark)),
        ],
      ),
    );
  }

  Widget _summaryBanner(bool isDark, int pending, int overlap, int shown) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1A2E1A), const Color(0xFF0F1F0F)]
              : [const Color(0xFFE8F5E9), const Color(0xFFF1F8E9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Teamoversikt', style: DriftProTheme.headingSm),
          const SizedBox(height: 6),
          Text(
            'Alle søknader og registreringer i ditt ansvarsområde. '
            'Se hvem som søker ferie i samme periode i avdelingen.',
            style: DriftProTheme.bodySm,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statPill('$pending ventende', DriftProTheme.warning),
              _statPill('$overlap med overlapp', Colors.orange.shade800),
              _statPill('$shown vist', DriftProTheme.primaryGreen),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
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

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        selectedColor: DriftProTheme.primaryGreen.withValues(alpha: 0.15),
        checkmarkColor: DriftProTheme.primaryGreen,
      ),
    );
  }

  Widget _requestCard(Absence a, bool isDark) {
    final days = widget.daysFor(a);
    final color = widget.colorForType(a.type);
    final overlaps = widget.overlapsByAbsenceId[a.id] ?? [];
    final hasOverlap = overlaps.isNotEmpty;
    final dept = a.departmentId != null ? widget.departmentNames[a.departmentId!] : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasOverlap && a.status == AbsenceStatus.ventende
              ? Colors.orange.shade400
              : (isDark ? DriftProTheme.dividerDark : Colors.grey.shade100),
          width: hasOverlap && a.status == AbsenceStatus.ventende ? 1.5 : 1,
        ),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.iconForType(a.type), color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              a.userName ?? 'Ansatt',
                              style: DriftProTheme.labelLg,
                            ),
                          ),
                          _statusBadge(a.status),
                        ],
                      ),
                      if (dept != null)
                        Text(dept, style: DriftProTheme.caption),
                      const SizedBox(height: 4),
                      Text(
                        '${a.type.label} · '
                        '${DateFormat('d. MMM').format(a.startDate)} – '
                        '${DateFormat('d. MMM').format(a.endDate)} ($days d.)',
                        style: DriftProTheme.bodySm,
                      ),
                      if (a.comment != null && a.comment!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '"${a.comment!}"',
                            style: DriftProTheme.bodySm.copyWith(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (hasOverlap)
            DepartmentLeaveTipCard(
              overlaps: overlaps,
              departmentName: dept,
              compact: true,
              isApprovalContext: a.status == AbsenceStatus.ventende,
            ),
          if (a.status == AbsenceStatus.ventende &&
              widget.onApprove != null &&
              widget.onReject != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => widget.onReject!(a),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Avvis'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => widget.onApprove!(a),
                      style: FilledButton.styleFrom(
                        backgroundColor: DriftProTheme.success,
                      ),
                      child: const Text('Godkjenn'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusBadge(AbsenceStatus status) {
    Color color;
    switch (status) {
      case AbsenceStatus.godkjent:
        color = DriftProTheme.success;
      case AbsenceStatus.avvist:
        color = DriftProTheme.error;
      case AbsenceStatus.ventende:
        color = DriftProTheme.warning;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
