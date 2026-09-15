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
  final ValueChanged<DateTime> onMonthChanged;
  final void Function(DateTime date, List<Absence> dayAbsences)? onDayTap;
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
    this.onDayTap,
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

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
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
          if (vacationOnly) ...[
            VacationYearMatrix(
              year: year,
              employees: filteredEmployees,
              vacations: filtered,
              onYearChanged: (y) {
                widget.onMonthChanged(DateTime(y, widget.month.month, 1));
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Månedskalender',
              style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
          ],
          TeamLeaveCalendar(
            month: widget.month,
            absences: filtered,
            employees: filteredEmployees,
            filterUserId: _userFilter,
            colorForType: widget.colorForType,
            typesFilter: types,
            includePending: true,
            onMonthChanged: widget.onMonthChanged,
            onDayTap: widget.onDayTap,
          ),
          const SizedBox(height: 12),
          LeaveCalendarMonthDigest(
            month: widget.month,
            absences: filtered,
            colorForType: widget.colorForType,
            vacationOnly: vacationOnly,
            showEntryList: hasEmployeeFilter,
          ),
          if (hasEmployeeFilter) ...[
            const SizedBox(height: 12),
            EmployeeLeaveTimeline(
              month: widget.month,
              employees: filteredEmployees,
              absences: filtered,
              colorForType: widget.colorForType,
              vacationOnly: vacationOnly,
              departmentNames: widget.departmentNames,
            ),
          ],
          if (!vacationOnly) ...[
            const SizedBox(height: 12),
            LeavePublicHolidaysPanel(year: year, initiallyExpanded: false),
          ],
          const SizedBox(height: 10),
          LeaveCalendarRulesSection(
            vacationTab: vacationOnly,
            companySettings: widget.companySettings,
          ),
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
