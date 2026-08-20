import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/absence/department_leave_conflict_service.dart';
import '../../../core/theme/absence_palette.dart';
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
    final border = isDark ? DriftProTheme.dividerDark : const Color(0xFFE2E8F0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Teamoversikt',
            style: DriftProTheme.headingSm.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Alle søknader i ditt ansvarsområde — godkjenn, avvis og se overlapp.',
            style: DriftProTheme.bodySm.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _KpiMini(
                  value: '$pending',
                  label: 'Ventende',
                  color: DriftProTheme.warning,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KpiMini(
                  value: '$overlap',
                  label: 'Med overlapp',
                  color: Colors.orange.shade800,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KpiMini(
                  value: '$shown',
                  label: 'Vist nå',
                  color: DriftProTheme.primaryGreen,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KpiMini(
                  value: '${widget.absences.length}',
                  label: 'Totalt',
                  color: AbsencePalette.indigo,
                ),
              ),
            ],
          ),
        ],
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
    final border = hasOverlap && a.status == AbsenceStatus.ventende
        ? Colors.orange.shade400
        : (isDark ? DriftProTheme.dividerDark : const Color(0xFFE2E8F0));
    final canAct = a.status == AbsenceStatus.ventende &&
        widget.onApprove != null &&
        widget.onReject != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: border,
          width: hasOverlap && a.status == AbsenceStatus.ventende ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.iconForType(a.type), color: color, size: 22),
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
                              style: DriftProTheme.labelLg.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          _statusBadge(a.status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _metaChip(a.type.label, color),
                          _metaChip('$days dager', AbsencePalette.slate),
                          if (dept != null) _metaChip(dept, AbsencePalette.indigo),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${DateFormat('EEE d. MMM', 'nb_NO').format(a.startDate)}'
                        ' – '
                        '${DateFormat('EEE d. MMM yyyy', 'nb_NO').format(a.endDate)}',
                        style: DriftProTheme.bodySm.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (a.comment != null && a.comment!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            a.comment!.trim(),
                            style: DriftProTheme.bodySm.copyWith(
                              color: isDark ? Colors.grey[400] : Colors.grey[700],
                              height: 1.35,
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
          if (canAct)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => widget.onReject!(a),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        minimumSize: const Size(0, 42),
                      ),
                      label: const Text('Avvis'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => widget.onApprove!(a),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      style: FilledButton.styleFrom(
                        backgroundColor: DriftProTheme.success,
                        minimumSize: const Size(0, 42),
                      ),
                      label: const Text('Godkjenn'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _metaChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
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
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _KpiMini extends StatelessWidget {
  const _KpiMini({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.grey[400] : Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}
