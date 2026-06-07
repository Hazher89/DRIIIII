import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/services/absence/department_leave_conflict_service.dart';
import '../../../core/services/absence/employee_leave_stats.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';
import 'department_leave_tip_card.dart';
import 'leave_calendar_month_digest.dart';
import 'leave_calendar_rules_section.dart';
import 'leave_absence_rate_widgets.dart';
import 'leave_employee_stats_panel.dart';
import 'leave_public_holidays_panel.dart';
import 'leave_employee_timeline.dart';
import 'team_leave_calendar.dart';

enum _StatusFilter { alle, ventende, godkjent, avvist }

enum _CategoryFilter { alle, ferie, fravaer }

enum _ViewMode { kalender, liste }

/// Kompakt team- og kalendervisning — kalenderen får maks plass.
class LeaveUnifiedTeamView extends StatefulWidget {
  final bool isManager;
  final DateTime month;
  final List<Absence> scopedAbsences;
  final List<UserProfile> teamProfiles;
  final List<AbsenceQuota> teamQuotas;
  final CompanyLeaveSettings companySettings;
  final int selectedYear;
  final Map<String, String> departmentNames;
  final Map<String, List<DepartmentLeaveOverlap>> overlapsByAbsenceId;
  final UserProfile? profile;
  final Color Function(AbsenceType) colorForType;
  final IconData Function(AbsenceType) iconForType;
  final int Function(Absence) daysFor;
  final ValueChanged<DateTime> onMonthChanged;
  final void Function(DateTime date, List<Absence> dayAbsences)? onDayTap;
  final Future<void> Function() onRefresh;
  final void Function(Absence absence)? onApprove;
  final void Function(Absence absence)? onReject;
  final String? initialUserFilter;
  final bool excludeSelfFromList;

  const LeaveUnifiedTeamView({
    super.key,
    required this.isManager,
    required this.month,
    required this.scopedAbsences,
    required this.teamProfiles,
    required this.teamQuotas,
    required this.companySettings,
    required this.selectedYear,
    required this.departmentNames,
    required this.overlapsByAbsenceId,
    required this.profile,
    required this.colorForType,
    required this.iconForType,
    required this.daysFor,
    required this.onMonthChanged,
    required this.onRefresh,
    this.onDayTap,
    this.onApprove,
    this.onReject,
    this.initialUserFilter,
    this.excludeSelfFromList = false,
  });

  @override
  State<LeaveUnifiedTeamView> createState() => _LeaveUnifiedTeamViewState();
}

class _LeaveUnifiedTeamViewState extends State<LeaveUnifiedTeamView> {
  final _searchCtrl = TextEditingController();
  String? _userFilter;
  String _search = '';
  _StatusFilter _status = _StatusFilter.alle;
  _CategoryFilter _category = _CategoryFilter.alle;
  _ViewMode _viewMode = _ViewMode.kalender;
  bool _showCalendarExtras = false;

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
    _searchCtrl.addListener(
      () => setState(() => _search = _searchCtrl.text.trim().toLowerCase()),
    );
  }

  @override
  void didUpdateWidget(covariant LeaveUnifiedTeamView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialUserFilter != oldWidget.initialUserFilter) {
      _userFilter = widget.initialUserFilter;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<UserProfile> get _employees {
    final base = widget.teamProfiles.isNotEmpty
        ? widget.teamProfiles
        : (widget.profile != null ? [widget.profile!] : <UserProfile>[]);
    if (_search.isEmpty) return base;
    return base
        .where((p) => p.fullName.toLowerCase().contains(_search))
        .toList();
  }

  UserProfile? get _selectedEmployee {
    if (_userFilter == null) return null;
    for (final p in _employees) {
      if (p.id == _userFilter) return p;
    }
    for (final p in widget.teamProfiles) {
      if (p.id == _userFilter) return p;
    }
    return null;
  }

  AbsenceQuota? _quotaFor(String userId) {
    for (final q in widget.teamQuotas) {
      if (q.userId == userId) return q;
    }
    return null;
  }

  List<Absence> get _calendarPool {
    return widget.scopedAbsences
        .where((a) =>
            a.status == AbsenceStatus.godkjent ||
            a.status == AbsenceStatus.ventende)
        .toList();
  }

  Set<AbsenceType> get _typeFilter {
    return switch (_category) {
      _CategoryFilter.ferie => {AbsenceType.ferie},
      _CategoryFilter.fravaer => _leaveTypes,
      _CategoryFilter.alle => {AbsenceType.ferie, ..._leaveTypes},
    };
  }

  List<Absence> get _filteredCalendarAbsences {
    var list = _calendarPool.where((a) => _typeFilter.contains(a.type)).toList();
    if (_userFilter != null) {
      list = list.where((a) => a.userId == _userFilter).toList();
    }
    return list;
  }

  List<Absence> get _filteredListAbsences {
    var list = [...widget.scopedAbsences];
    if (widget.excludeSelfFromList && widget.profile != null) {
      list = list.where((a) => a.userId != widget.profile!.id).toList();
    }
    if (_userFilter != null) {
      list = list.where((a) => a.userId == _userFilter).toList();
    } else if (_search.isNotEmpty) {
      list = list.where((a) {
        final name = (a.userName ?? '').toLowerCase();
        return name.contains(_search);
      }).toList();
    }
    list.sort((a, b) => b.startDate.compareTo(a.startDate));
    return list.where((a) {
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
      switch (_category) {
        case _CategoryFilter.alle:
          break;
        case _CategoryFilter.ferie:
          if (a.type != AbsenceType.ferie) return false;
        case _CategoryFilter.fravaer:
          if (a.type == AbsenceType.ferie) return false;
      }
      return true;
    }).toList();
  }

  List<Absence> _absencesForUser(String userId) {
    return widget.scopedAbsences.where((a) => a.userId == userId).toList();
  }

  int get _activeFilterCount {
    var n = 0;
    if (_category != _CategoryFilter.alle) n++;
    if (_status != _StatusFilter.alle) n++;
    return n;
  }

  String get _employeeLabel {
    final selected = _selectedEmployee;
    if (selected == null) return 'Hele teamet';
    final parts = selected.fullName.split(' ');
    if (parts.length >= 2) {
      return '${parts.first} ${parts.last[0]}.';
    }
    return selected.fullName;
  }

  TeamLeaveSummary _summaryFor(UserProfile? selected) {
    final employees = selected != null ? [selected] : _employees;
    return TeamLeaveSummary.compute(
      employees: employees,
      allAbsences: widget.scopedAbsences,
      company: widget.companySettings,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = _selectedEmployee;
    final calendarEmployees = _userFilter != null && selected != null
        ? [selected]
        : _employees;
    final pending = widget.scopedAbsences
        .where((a) => a.status == AbsenceStatus.ventende)
        .length;
    final list = _filteredListAbsences;
    final vacationOnly = _category == _CategoryFilter.ferie;
    final showPicker = widget.teamProfiles.length > 1 || widget.isManager;

    return Column(
      children: [
        _buildCommandBar(isDark, showPicker, pending, list.length),
        LeaveAbsenceSummaryBar(
          summary: _summaryFor(selected),
          title: selected != null
              ? 'Fravær ${selected.fullName}'
              : 'Fravær snitt teamet',
          subtitle: selected != null
              ? 'Dager og tilfeller for valgt ansatt'
              : '${_employees.length} ansatte · fravær % av virkedager YTD',
        ),
        if (selected != null)
          LeaveEmployeeStatsCompactBar(
            employee: selected,
            quota: _quotaFor(selected.id),
            company: widget.companySettings,
            selectedYear: widget.selectedYear,
            employeeAbsences: _absencesForUser(selected.id),
            onTapDetails: () => LeaveEmployeeStatsPanel.showSheet(
              context,
              employee: selected,
              quota: _quotaFor(selected.id),
              company: widget.companySettings,
              selectedYear: widget.selectedYear,
              employeeAbsences: _absencesForUser(selected.id),
              departmentNames: widget.departmentNames,
            ),
          )
        else if (widget.isManager && (pending > 0 || _overlapPendingCount > 0))
          _teamAlertsBar(isDark, pending),
        Expanded(
          child: _viewMode == _ViewMode.kalender
              ? RefreshIndicator(
                  onRefresh: widget.onRefresh,
                  child: _buildCalendarBody(
                    isDark,
                    selected,
                    calendarEmployees,
                    vacationOnly,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: widget.onRefresh,
                  child: _buildListBody(isDark, list, selected),
                ),
        ),
      ],
    );
  }

  Widget _buildCommandBar(
    bool isDark,
    bool showPicker,
    int pending,
    int listCount,
  ) {
    return Material(
      elevation: 0.5,
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(
            children: [
              if (showPicker)
                Expanded(
                  child: InkWell(
                    onTap: _openEmployeePicker,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? DriftProTheme.surfaceDark
                            : const Color(0xFFF4FAF5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: DriftProTheme.primaryGreen.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _userFilter != null
                                ? Icons.person
                                : Icons.groups_outlined,
                            size: 18,
                            color: DriftProTheme.primaryGreen,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _employeeLabel,
                              style: DriftProTheme.labelSm.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.expand_more,
                            size: 18,
                            color: isDark ? Colors.white54 : Colors.grey.shade600,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: 8),
              _viewToggle(isDark, listCount),
              const SizedBox(width: 4),
              _filterButton(isDark, pending),
            ],
          ),
        ),
      ),
    );
  }

  Widget _viewToggle(bool isDark, int listCount) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.surfaceDark : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewChip(
            isDark,
            icon: Icons.calendar_month_outlined,
            selected: _viewMode == _ViewMode.kalender,
            onTap: () => setState(() => _viewMode = _ViewMode.kalender),
          ),
          _viewChip(
            isDark,
            icon: Icons.list_alt,
            label: listCount > 0 ? '$listCount' : null,
            selected: _viewMode == _ViewMode.liste,
            onTap: () => setState(() => _viewMode = _ViewMode.liste),
          ),
        ],
      ),
    );
  }

  Widget _viewChip(
    bool isDark, {
    required IconData icon,
    String? label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? DriftProTheme.cardDark : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected
                  ? DriftProTheme.primaryGreen
                  : (isDark ? Colors.white54 : Colors.grey.shade600),
            ),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? DriftProTheme.primaryGreen
                      : (isDark ? Colors.white54 : Colors.grey.shade600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filterButton(bool isDark, int pending) {
    final active = _activeFilterCount;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Filter',
          onPressed: _openFilterSheet,
          icon: Icon(
            Icons.tune_rounded,
            color: active > 0
                ? DriftProTheme.primaryGreen
                : (isDark ? Colors.white70 : Colors.grey.shade700),
          ),
        ),
        if (active > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: DriftProTheme.primaryGreen,
                shape: BoxShape.circle,
              ),
            ),
          )
        else if (pending > 0 && _status != _StatusFilter.ventende)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: DriftProTheme.warning,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$pending',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  int get _overlapPendingCount => widget.scopedAbsences.where((a) {
        final o = widget.overlapsByAbsenceId[a.id] ?? [];
        return o.isNotEmpty && a.status == AbsenceStatus.ventende;
      }).length;

  Widget _teamAlertsBar(bool isDark, int pending) {
    return Material(
      color: isDark ? DriftProTheme.surfaceDark : const Color(0xFFFFF8E1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            if (pending > 0)
              Text(
                '$pending ventende godkjenning',
                style: DriftProTheme.caption.copyWith(
                  color: DriftProTheme.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (pending > 0 && _overlapPendingCount > 0)
              Text(' · ', style: DriftProTheme.caption),
            if (_overlapPendingCount > 0)
              Text(
                '$_overlapPendingCount overlapp i avdeling',
                style: DriftProTheme.caption.copyWith(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarBody(
    bool isDark,
    UserProfile? selected,
    List<UserProfile> calendarEmployees,
    bool vacationOnly,
  ) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: TeamLeaveCalendar(
              month: widget.month,
              absences: _filteredCalendarAbsences,
              employees: calendarEmployees,
              filterUserId: _userFilter,
              colorForType: widget.colorForType,
              typesFilter: _typeFilter,
              includePending: true,
              onMonthChanged: widget.onMonthChanged,
              onDayTap: widget.onDayTap,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _calendarExtrasToggle(isDark),
        ),
        if (_showCalendarExtras) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _category == _CategoryFilter.alle
                  ? LeaveCalendarMonthDigest(
                      month: widget.month,
                      absences: _filteredCalendarAbsences,
                      colorForType: widget.colorForType,
                      vacationOnly: false,
                      showEntryList: _userFilter != null,
                    )
                  : LeaveCalendarMonthDigest(
                      month: widget.month,
                      absences: _filteredCalendarAbsences,
                      colorForType: widget.colorForType,
                      vacationOnly: _category == _CategoryFilter.ferie,
                      showEntryList: _userFilter != null,
                    ),
            ),
          ),
          if (_userFilter != null && selected != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: EmployeeLeaveTimeline(
                  month: widget.month,
                  employees: [selected],
                  absences: _filteredCalendarAbsences,
                  colorForType: widget.colorForType,
                  vacationOnly: vacationOnly,
                  departmentNames: widget.departmentNames,
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              child: LeavePublicHolidaysPanel(
                year: widget.month.year,
                initiallyExpanded: false,
              ),
            ),
          ),
        ] else
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  Widget _calendarExtrasToggle(bool isDark) {
    return Center(
      child: TextButton.icon(
        onPressed: () => setState(() => _showCalendarExtras = !_showCalendarExtras),
        icon: Icon(
          _showCalendarExtras ? Icons.expand_less : Icons.expand_more,
          size: 18,
        ),
        label: Text(
          _showCalendarExtras ? 'Skjul detaljer' : 'Vis månedssammendrag & helligdager',
          style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildListBody(bool isDark, List<Absence> list, UserProfile? selected) {
    if (list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Center(child: Text('Ingen treff', style: DriftProTheme.headingSm)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _userFilter != null
                  ? 'Ingen registreringer for ${selected?.fullName ?? 'ansatt'} med valgte filtre.'
                  : 'Prøv et annet filter eller velg en ansatt.',
              style: DriftProTheme.bodySm,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: list.length + 1,
      itemBuilder: (context, i) {
        if (i == list.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LeaveCalendarRulesSection(
              vacationTab: _category != _CategoryFilter.fravaer,
              companySettings: widget.companySettings,
            ),
          );
        }
        return _requestCard(list[i], isDark);
      },
    );
  }

  Future<void> _openEmployeePicker() async {
    _searchCtrl.clear();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtered = _employees;
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.55,
              minChildSize: 0.35,
              maxChildSize: 0.85,
              builder: (_, scrollCtrl) {
                return Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text('Velg ansatt', style: DriftProTheme.headingSm),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _searchCtrl,
                        autofocus: true,
                        onChanged: (_) => setSheetState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Søk navn…',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          filled: true,
                          fillColor: isDark
                              ? DriftProTheme.surfaceDark
                              : Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        controller: scrollCtrl,
                        children: [
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                              child: const Icon(
                                Icons.groups,
                                color: DriftProTheme.primaryGreen,
                                size: 20,
                              ),
                            ),
                            title: const Text('Hele teamet'),
                            subtitle: Text(
                              '${widget.teamProfiles.length} ansatte',
                              style: DriftProTheme.caption,
                            ),
                            selected: _userFilter == null,
                            onTap: () {
                              setState(() => _userFilter = null);
                              Navigator.pop(ctx);
                            },
                          ),
                          ...filtered.map(
                            (p) => ListTile(
                              leading: CircleAvatar(
                                backgroundColor: DriftProTheme.primaryGreen
                                    .withValues(alpha: 0.12),
                                child: Text(
                                  p.fullName.isNotEmpty
                                      ? p.fullName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: DriftProTheme.primaryGreen,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(p.fullName),
                              subtitle: p.employeeNumber != null
                                  ? Text('nr ${p.employeeNumber}',
                                      style: DriftProTheme.caption)
                                  : null,
                              selected: _userFilter == p.id,
                              onTap: () {
                                setState(() => _userFilter = p.id);
                                Navigator.pop(ctx);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _openFilterSheet() async {
    var cat = _category;
    var stat = _status;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Filter', style: DriftProTheme.headingSm),
                  const SizedBox(height: 16),
                  Text('Type', style: DriftProTheme.labelSm),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _filterChip('Alle', cat == _CategoryFilter.alle, () {
                        setSheetState(() => cat = _CategoryFilter.alle);
                      }),
                      _filterChip('Ferie', cat == _CategoryFilter.ferie, () {
                        setSheetState(() => cat = _CategoryFilter.ferie);
                      }),
                      _filterChip('Fravær', cat == _CategoryFilter.fravaer, () {
                        setSheetState(() => cat = _CategoryFilter.fravaer);
                      }),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Status', style: DriftProTheme.labelSm),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _filterChip('Alle', stat == _StatusFilter.alle, () {
                        setSheetState(() => stat = _StatusFilter.alle);
                      }),
                      _filterChip('Ventende', stat == _StatusFilter.ventende, () {
                        setSheetState(() => stat = _StatusFilter.ventende);
                      }),
                      _filterChip('Godkjent', stat == _StatusFilter.godkjent, () {
                        setSheetState(() => stat = _StatusFilter.godkjent);
                      }),
                      _filterChip('Avvist', stat == _StatusFilter.avvist, () {
                        setSheetState(() => stat = _StatusFilter.avvist);
                      }),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          setSheetState(() {
                            cat = _CategoryFilter.alle;
                            stat = _StatusFilter.alle;
                          });
                        },
                        child: const Text('Nullstill'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _category = cat;
                            _status = stat;
                          });
                          Navigator.pop(ctx);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: DriftProTheme.primaryGreen,
                        ),
                        child: const Text('Bruk filter'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: DriftProTheme.primaryGreen.withValues(alpha: 0.15),
      checkmarkColor: DriftProTheme.primaryGreen,
    );
  }

  Widget _requestCard(Absence a, bool isDark) {
    final days = widget.daysFor(a);
    final color = widget.colorForType(a.type);
    final overlaps = widget.overlapsByAbsenceId[a.id] ?? [];
    final hasOverlap = overlaps.isNotEmpty;
    final dept =
        a.departmentId != null ? widget.departmentNames[a.departmentId!] : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasOverlap && a.status == AbsenceStatus.ventende
              ? Colors.orange.shade400
              : (isDark ? DriftProTheme.dividerDark : Colors.grey.shade100),
          width: hasOverlap && a.status == AbsenceStatus.ventende ? 1.5 : 1,
        ),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
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
                              style: DriftProTheme.labelLg,
                            ),
                          ),
                          _statusBadge(a.status),
                        ],
                      ),
                      if (dept != null) Text(dept, style: DriftProTheme.caption),
                      const SizedBox(height: 4),
                      Text(
                        '${a.type.label} · '
                        '${DateFormat('d. MMM').format(a.startDate)} – '
                        '${DateFormat('d. MMM').format(a.endDate)} ($days d.)',
                        style: DriftProTheme.bodySm,
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
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => widget.onReject!(a),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Avvis'),
                    ),
                  ),
                  const SizedBox(width: 10),
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
    final color = switch (status) {
      AbsenceStatus.godkjent => DriftProTheme.success,
      AbsenceStatus.avvist => DriftProTheme.error,
      AbsenceStatus.ventende => DriftProTheme.warning,
    };
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
