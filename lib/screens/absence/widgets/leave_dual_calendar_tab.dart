import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';
import '../../../core/constants/leave_rules.dart';
import '../../../core/utils/norwegian_holidays.dart';
import 'leave_calendar_month_digest.dart';
import 'leave_calendar_rules_section.dart';
import 'leave_employee_timeline.dart';
import 'leave_public_holidays_panel.dart';
import 'team_leave_calendar.dart';

/// To kalendere: ferie og øvrig fravær — avansert oversikt for hele teamet.
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

class _LeaveDualCalendarTabState extends State<LeaveDualCalendarTab>
    with SingleTickerProviderStateMixin {
  late TabController _inner;
  String? _userFilter;

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
    _inner = TabController(length: 2, vsync: this);
  }

  @override
  void didUpdateWidget(covariant LeaveDualCalendarTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialUserFilter != oldWidget.initialUserFilter) {
      _userFilter = widget.initialUserFilter;
    }
  }

  @override
  void dispose() {
    _inner.dispose();
    super.dispose();
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
    final year = widget.month.year;

    return Column(
      children: [
        _heroHeader(isDark, year),
        Material(
          color: isDark ? DriftProTheme.cardDark : Colors.white,
          child: TabBar(
            controller: _inner,
            labelColor: DriftProTheme.primaryGreen,
            unselectedLabelColor: isDark ? Colors.white54 : Colors.grey.shade600,
            indicatorColor: DriftProTheme.primaryGreen,
            tabs: const [
              Tab(icon: Icon(Icons.beach_access_outlined, size: 20), text: 'Feriekalender'),
              Tab(icon: Icon(Icons.sick_outlined, size: 20), text: 'Fraværskalender'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _inner,
            children: [
              _calendarPane(vacationOnly: true, types: _vacationTypes),
              _calendarPane(vacationOnly: false, types: _leaveTypes),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroHeader(bool isDark, int year) {
    final employees = widget.teamProfiles.isNotEmpty
        ? widget.teamProfiles
        : (widget.profile != null ? [widget.profile!] : <UserProfile>[]);
    final showEmployeePicker = employees.length > 1;
    final nextHoliday = NorwegianHolidays.upcomingFrom(DateTime.now()).firstOrNull;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : const Color(0xFFF4FAF5),
        border: Border(
          bottom: BorderSide(
            color: DriftProTheme.primaryGreen.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Kalender $year', style: DriftProTheme.headingSm),
                    const SizedBox(height: 2),
                    Text(
                      showEmployeePicker
                          ? 'Velg ansatt for detaljer, eller se hele teamet i kalenderen.'
                          : 'Måned, uke og år — markert med ferie og fravær.',
                      style: DriftProTheme.caption.copyWith(
                        color: isDark ? Colors.white54 : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              if (nextHoliday != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Icon(
                    Icons.event_busy,
                    size: 18,
                    color: Colors.red.shade700,
                  ),
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Alle — teamkalender'),
                ),
                ...employees.map(
                  (p) => DropdownMenuItem(value: p.id, child: Text(p.fullName)),
                ),
              ],
              onChanged: (v) => setState(() => _userFilter = v),
            ),
          ],
        ],
      ),
    );
  }

  Widget _calendarPane({
    required bool vacationOnly,
    required Set<AbsenceType> types,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final employees = widget.teamProfiles.isNotEmpty
        ? widget.teamProfiles
        : (widget.profile != null ? [widget.profile!] : <UserProfile>[]);
    final filtered = _filterTypes(types);
    final hasEmployeeFilter = _userFilter != null;
    final filteredEmployees = hasEmployeeFilter
        ? employees.where((e) => e.id == _userFilter).toList()
        : employees;
    final year = widget.month.year;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            const SizedBox(height: 12),
            LeavePublicHolidaysPanel(year: year, initiallyExpanded: false),
            const SizedBox(height: 10),
            LeaveCalendarRulesSection(
              vacationTab: vacationOnly,
              companySettings: widget.companySettings,
            ),
            if (!widget.isManager && !hasEmployeeFilter)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Velg en kollega i listen over for å se detaljer. '
                  'Sjekk kalenderen før du søker ferie.',
                  style: DriftProTheme.caption.copyWith(
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
