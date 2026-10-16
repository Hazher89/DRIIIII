import 'package:flutter/material.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/common/team_equal_controls.dart';
import 'leave_calendar_month_digest.dart';
import 'leave_calendar_rules_section.dart';
import 'leave_employee_timeline.dart';
import 'leave_public_holidays_panel.dart';
import 'team_leave_calendar.dart';
import 'vacation_year_matrix.dart';

enum _CalKind { ferie, fravaer }

/// To kalendere: ferie og øvrig fravær — alt scroller med siden.
class LeaveDualCalendarTab extends StatefulWidget {
  final bool isManager;
  final DateTime month;
  final List<Absence> scopedAbsences;
  final List<UserProfile> teamProfiles;
  final List<AbsenceQuota> teamQuotas;
  final CompanyLeaveSettings companySettings;
  final int selectedYear;
  final Map<String, String> departmentNames;
  final UserProfile? profile;
  final Color Function(AbsenceType) colorForType;
  final IconData Function(AbsenceType)? iconForType;
  final ValueChanged<DateTime> onMonthChanged;
  final void Function(DateTime date, List<Absence> dayAbsences)? onDayTap;
  final void Function(Absence absence)? onAbsenceTap;
  final Future<void> Function() onRefresh;
  final String? initialUserFilter;

  const LeaveDualCalendarTab({
    super.key,
    required this.isManager,
    required this.month,
    required this.scopedAbsences,
    required this.teamProfiles,
    required this.teamQuotas,
    required this.companySettings,
    required this.selectedYear,
    required this.departmentNames,
    required this.profile,
    required this.colorForType,
    required this.onMonthChanged,
    required this.onRefresh,
    this.iconForType,
    this.onDayTap,
    this.onAbsenceTap,
    this.initialUserFilter,
  });

  @override
  State<LeaveDualCalendarTab> createState() => _LeaveDualCalendarTabState();
}

class _LeaveDualCalendarTabState extends State<LeaveDualCalendarTab> {
  String? _userFilter;
  _CalKind _kind = _CalKind.ferie;

  static const _vacationTypes = {AbsenceType.ferie};
  static const _leaveTypes = {
    AbsenceType.egenmelding,
    AbsenceType.syktBarn,
    AbsenceType.permisjon,
    AbsenceType.sykmelding,
  };

  @override
  void initState() {
    super.initState();
    _userFilter = widget.initialUserFilter;
  }

  @override
  void didUpdateWidget(covariant LeaveDualCalendarTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialUserFilter != oldWidget.initialUserFilter) {
      _userFilter = widget.initialUserFilter;
    }
  }

  List<Absence> get _calendarPool {
    return widget.scopedAbsences
        .where((a) =>
            a.status == AbsenceStatus.godkjent ||
            a.status == AbsenceStatus.ventende)
        .toList();
  }

  List<Absence> _filterTypes(Set<AbsenceType> types) {
    return _calendarPool.where((a) => types.contains(a.type)).toList();
  }

  Widget _awayTodayCard(List<Absence> pool, bool isDark) {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final hits = pool.where((a) {
      final start = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
      final end = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
      return !day.isBefore(start) && !day.isAfter(end);
    }).toList();
    final names = hits
        .map((a) => a.userName?.trim().isNotEmpty == true ? a.userName!.trim() : 'Ansatt')
        .toSet()
        .toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: names.isEmpty
            ? (isDark ? const Color(0xFF1C2822) : const Color(0xFFF4F7F5))
            : DriftProTheme.primaryGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        names.isEmpty
            ? 'Ingen er borte i dag.'
            : 'Borte i dag: ${names.join(', ')}',
        style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  void _handleDayTap(DateTime date, List<Absence> dayAbsences) {
    if (widget.onDayTap != null) {
      widget.onDayTap!(date, dayAbsences);
      return;
    }
    if (widget.onAbsenceTap == null) return;
    if (dayAbsences.isEmpty) return;
    if (dayAbsences.length == 1) {
      widget.onAbsenceTap!(dayAbsences.first);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${date.day}.${date.month.toString().padLeft(2, '0')}.${date.year}',
                style: DriftProTheme.headingSm,
              ),
              const SizedBox(height: 8),
              ...dayAbsences.map((a) {
                final pending = a.status == AbsenceStatus.ventende;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    widget.iconForType?.call(a.type) ?? Icons.event,
                    color: widget.colorForType(a.type),
                  ),
                  title: Text(a.userName ?? 'Ansatt'),
                  subtitle: Text(
                    '${a.type.label} · ${a.status.label}'
                    '${pending && widget.isManager ? ' · trykk for å behandle' : ''}',
                  ),
                  trailing: pending && widget.isManager
                      ? const Icon(Icons.gavel_outlined, size: 18)
                      : const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onAbsenceTap?.call(a);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final vacationOnly = _kind == _CalKind.ferie;
    final types = vacationOnly ? _vacationTypes : _leaveTypes;
    final employees = widget.teamProfiles.isNotEmpty
        ? widget.teamProfiles
        : (widget.profile != null ? [widget.profile!] : <UserProfile>[]);
    final filtered = _filterTypes(types);
    final hasEmployeeFilter = _userFilter != null;
    final filteredEmployees = hasEmployeeFilter
        ? employees.where((e) => e.id == _userFilter).toList()
        : employees;
    final year = widget.month.year;
    final showEmployeePicker = employees.length > 1;

    final wide = MediaQuery.sizeOf(context).width >= 900;
    final padH = wide ? 20.0 : 12.0;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(padH, 8, padH, wide ? 28 : 120),
        children: [
          TeamEqualSegmentBar<_CalKind>(
            value: _kind,
            onChanged: (v) => setState(() => _kind = v),
            items: const [
              TeamEqualSegmentItem(
                value: _CalKind.ferie,
                label: 'Ferie',
                icon: Icons.beach_access_outlined,
              ),
              TeamEqualSegmentItem(
                value: _CalKind.fravaer,
                label: 'Fravær',
                icon: Icons.sick_outlined,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              vacationOnly
                  ? 'Feriekalender — trykk en dag for detaljer. Godkjent og ventende vises med farge.'
                  : 'Fraværskalender — egenmelding, sykmelding, sykt barn og permisjon med egne farger.',
              style: DriftProTheme.bodySm.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.grey.shade800,
              ),
            ),
          ),
          if (showEmployeePicker) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              value: _userFilter,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Ansatt',
                prefixIcon: const Icon(Icons.person_outline, size: 20),
                filled: true,
                fillColor: isDark ? DriftProTheme.surfaceDark : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Alle — teamkalender'),
                ),
                ...employees.map(
                  (p) => DropdownMenuItem(
                    value: p.id,
                    child: Text(p.fullName),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _userFilter = v),
            ),
          ],
          const SizedBox(height: 12),
          if (widget.isManager) ...[
            _awayTodayCard(filtered, isDark),
            const SizedBox(height: 12),
          ],
          if (vacationOnly && !wide) ...[
            TeamLeaveCalendar(
              month: widget.month,
              absences: filtered,
              employees: filteredEmployees,
              filterUserId: _userFilter,
              colorForType: widget.colorForType,
              typesFilter: types,
              includePending: true,
              onMonthChanged: widget.onMonthChanged,
              onDayTap: _handleDayTap,
            ),
            const SizedBox(height: 12),
            LeaveCalendarMonthDigest(
              month: widget.month,
              absences: filtered,
              colorForType: widget.colorForType,
              vacationOnly: true,
              showEntryList: true,
            ),
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Årsmatrise',
                  style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('Uke for uke. Best på stor skjerm.'),
                children: [
                  VacationYearMatrix(
                    year: year,
                    employees: filteredEmployees,
                    vacations: filtered,
                    canManage: widget.isManager,
                    onAbsenceTap: widget.onAbsenceTap,
                    onYearChanged: (y) {
                      widget.onMonthChanged(DateTime(y, widget.month.month, 1));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            LeavePublicHolidaysPanel(year: year, initiallyExpanded: false),
          ] else if (vacationOnly) ...[
            TeamLeaveCalendar(
              month: widget.month,
              absences: filtered,
              employees: filteredEmployees,
              filterUserId: _userFilter,
              colorForType: widget.colorForType,
              typesFilter: types,
              includePending: true,
              onMonthChanged: widget.onMonthChanged,
              onDayTap: _handleDayTap,
            ),
            const SizedBox(height: 12),
            LeaveCalendarMonthDigest(
              month: widget.month,
              absences: filtered,
              colorForType: widget.colorForType,
              vacationOnly: true,
              showEntryList: true,
            ),
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(
                  'Årsmatrise',
                  style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('Uke for uke for hele året'),
                children: [
                  VacationYearMatrix(
                    year: year,
                    employees: filteredEmployees,
                    vacations: filtered,
                    canManage: widget.isManager,
                    onAbsenceTap: widget.onAbsenceTap,
                    onYearChanged: (y) {
                      widget.onMonthChanged(DateTime(y, widget.month.month, 1));
                    },
                  ),
                ],
              ),
            ),
          ] else ...[
            // Samme kalenderkvalitet som ferie — måned først + tydelig fargeforklaring.
            TeamLeaveCalendar(
              month: widget.month,
              absences: filtered,
              employees: filteredEmployees,
              filterUserId: _userFilter,
              colorForType: widget.colorForType,
              typesFilter: types,
              includePending: true,
              onMonthChanged: widget.onMonthChanged,
              onDayTap: _handleDayTap,
            ),
            const SizedBox(height: 12),
            LeaveCalendarMonthDigest(
              month: widget.month,
              absences: filtered,
              colorForType: widget.colorForType,
              vacationOnly: false,
              showEntryList: true,
            ),
            if (hasEmployeeFilter || wide) ...[
              const SizedBox(height: 12),
              EmployeeLeaveTimeline(
                month: widget.month,
                employees: filteredEmployees,
                absences: filtered,
                colorForType: widget.colorForType,
                vacationOnly: false,
                departmentNames: widget.departmentNames,
              ),
            ],
            const SizedBox(height: 12),
            LeavePublicHolidaysPanel(year: year, initiallyExpanded: false),
            const SizedBox(height: 10),
            LeaveCalendarRulesSection(
              vacationTab: false,
              companySettings: widget.companySettings,
            ),
          ],
          if (!widget.isManager && !hasEmployeeFilter)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Velg en kollega for detaljer. Sjekk kalenderen før du søker ferie.',
                style: DriftProTheme.caption.copyWith(
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
