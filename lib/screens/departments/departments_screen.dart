import 'package:flutter/material.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/leave_rules.dart';
import '../../core/services/absence/employee_leave_stats.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/absence.dart';
import '../../models/department.dart';
import '../../models/user_profile.dart';
import 'widgets/department_absence_stats.dart';
import '../more/organization_chart_screen.dart';
import 'department_details_screen.dart';
import 'widgets/department_grid_card.dart';
import 'widgets/department_ui_helpers.dart';
import '../absence/widgets/leave_absence_rate_widgets.dart';
import 'widgets/unassigned_employees_banner.dart';
import '../../widgets/driftpro_loading_indicator.dart';

enum _DepartmentFilter { all, needsLeader, hasMembers, empty }

enum _DepartmentSort { name, membersDesc, membersAsc }

class DepartmentsScreen extends StatefulWidget {
  const DepartmentsScreen({super.key});

  @override
  State<DepartmentsScreen> createState() => _DepartmentsScreenState();
}

class _DepartmentsScreenState extends State<DepartmentsScreen> {
  List<Department> _departments = [];
  List<UserProfile> _profiles = [];
  Map<String, UserProfile> _profileById = {};
  Map<String, List<UserProfile>> _membersByDept = {};
  Map<String, DepartmentAbsenceOverview> _absenceByDept = {};
  List<Absence> _absences = [];
  CompanyLeaveSettings _companySettings = const CompanyLeaveSettings();
  bool _isLoading = true;
  String? _error;
  String _search = '';
  _DepartmentFilter _filter = _DepartmentFilter.all;
  _DepartmentSort _sort = _DepartmentSort.name;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId == null) throw Exception('Selskap ikke funnet');

      final profile = await SupabaseService.fetchCurrentUserProfile();
      final departments = await SupabaseService.fetchDepartments(companyId: companyId);
      final profiles = (await SupabaseService.fetchProfiles(companyId: companyId))
          .where((p) => !p.isPartnerPortalUser && p.isActive)
          .toList();
      final absences = profile != null
          ? await SupabaseService.fetchScopedAbsences(profile: profile)
          : await SupabaseService.fetchAbsences(companyId: companyId);
      final companySettings = await SupabaseService.fetchCompanyLeaveSettings(companyId);

      final membersByDept = <String, List<UserProfile>>{};
      for (final p in profiles) {
        final deptId = p.departmentId;
        if (deptId == null || deptId.isEmpty) continue;
        membersByDept.putIfAbsent(deptId, () => []).add(p);
      }
      for (final list in membersByDept.values) {
        list.sort((a, b) => a.fullName.compareTo(b.fullName));
      }

      final absenceByDept = DepartmentAbsenceStats.forAllDepartments(
        departmentIds: departments.map((d) => d.id),
        membersByDept: membersByDept,
        allAbsences: absences,
        company: companySettings,
      );

      setState(() {
        _departments = departments;
        _profiles = profiles;
        _profileById = {for (final p in profiles) p.id: p};
        _membersByDept = membersByDept;
        _absences = absences;
        _absenceByDept = absenceByDept;
        _companySettings = companySettings;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Feil ved henting av avdelinger: $e';
        _isLoading = false;
      });
    }
  }

  List<UserProfile> get _unassigned =>
      _profiles.where((p) => p.departmentId == null || p.departmentId!.isEmpty).toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName));

  List<UserProfile> get _assignedProfiles =>
      _profiles.where((p) => p.departmentId != null && p.departmentId!.isNotEmpty).toList();

  TeamLeaveSummary get _companyLeaveSummary => TeamLeaveSummary.compute(
        employees: _assignedProfiles,
        allAbsences: _absences,
        company: _companySettings,
      );

  List<Department> get _visibleDepartments {
    var list = List<Department>.from(_departments);

    if (_search.trim().isNotEmpty) {
      final q = _search.trim().toLowerCase();
      list = list.where((d) {
        if (d.name.toLowerCase().contains(q)) return true;
        if ((d.description ?? '').toLowerCase().contains(q)) return true;
        final leaders = DepartmentUiHelpers.leadersFor(d, _profileById);
        return leaders.any((l) => l.fullName.toLowerCase().contains(q));
      }).toList();
    }

    list = list.where((d) {
      final count = DepartmentUiHelpers.membersFor(d, _membersByDept).length;
      switch (_filter) {
        case _DepartmentFilter.all:
          return true;
        case _DepartmentFilter.needsLeader:
          return d.leaderIds.isEmpty;
        case _DepartmentFilter.hasMembers:
          return count > 0;
        case _DepartmentFilter.empty:
          return count == 0;
      }
    }).toList();

    list.sort((a, b) {
      final aCount = DepartmentUiHelpers.membersFor(a, _membersByDept).length;
      final bCount = DepartmentUiHelpers.membersFor(b, _membersByDept).length;
      switch (_sort) {
        case _DepartmentSort.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _DepartmentSort.membersDesc:
          return bCount.compareTo(aCount);
        case _DepartmentSort.membersAsc:
          return aCount.compareTo(bCount);
      }
    });

    return list;
  }

  Future<void> _openDepartment(Department dept) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DepartmentDetailsScreen(department: dept),
      ),
    );
    if (mounted) await _loadData();
  }

  Future<void> _createNewDepartment() async {
    final companyId = await SupabaseService.getCurrentCompanyId();
    if (companyId == null) return;

    final newDept = Department(
      id: '',
      companyId: companyId,
      name: 'Ny avdeling',
      description: '',
      colorCode: '#2E7D32',
      iconName: 'business',
    );

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DepartmentDetailsScreen(department: newDept, isNew: true),
      ),
    );
    if (mounted) await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.bgDark : DriftProTheme.bgLight,
      floatingActionButton: _isLoading || _error != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _createNewDepartment,
              backgroundColor: DriftProTheme.primaryGreen,
              icon: const Icon(AppIcons.add),
              label: const Text('Ny avdeling'),
            ),
      body: _isLoading
          ? const DriftProLoadingCenter()
          : _error != null
              ? _buildError(isDark)
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverAppBar(
                        pinned: true,
                        title: const Text('Avdelinger'),
                        actions: [
                          IconButton(
                            icon: const Icon(Icons.account_tree_rounded),
                            tooltip: 'Organisasjonskart',
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const OrganizationChartScreen(),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded),
                            tooltip: 'Oppdater',
                            onPressed: _loadData,
                          ),
                        ],
                      ),
                      if (_companyLeaveSummary.employeeCount > 0)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: LeaveAbsenceSummaryBar(
                              summary: _companyLeaveSummary,
                              title: 'Fravær snitt bedriften',
                              subtitle: '${_assignedProfiles.length} ansatte med avdeling',
                            ),
                          ),
                        ),
                      SliverToBoxAdapter(child: _buildToolbar(isDark)),
                      SliverToBoxAdapter(
                        child: UnassignedEmployeesBanner(
                          employees: _unassigned,
                          initiallyExpanded: _unassigned.length <= 5,
                        ),
                      ),
                      if (_departments.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(isDark),
                        )
                      else if (_visibleDepartments.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildNoResults(isDark),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                          sliver: SliverLayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.crossAxisExtent;
                              final columns = width >= 1100
                                  ? 3
                                  : width >= 720
                                      ? 2
                                      : 1;
                              if (columns == 1) {
                                return SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      final dept = _visibleDepartments[index];
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: _departmentCard(dept),
                                      );
                                    },
                                    childCount: _visibleDepartments.length,
                                  ),
                                );
                              }
                              return SliverGrid(
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: columns == 3 ? 0.62 : 0.58,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) => _departmentCard(_visibleDepartments[index]),
                                  childCount: _visibleDepartments.length,
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _departmentCard(Department dept) {
    final members = DepartmentUiHelpers.membersFor(dept, _membersByDept);
    return DepartmentGridCard(
      department: dept,
      members: members,
      leaders: DepartmentUiHelpers.leadersFor(dept, _profileById),
      absenceStats: _absenceByDept[dept.id] ??
          DepartmentAbsenceStats.forDepartment(
            departmentId: dept.id,
            members: members,
            allAbsences: _absences,
          ),
      onTap: () => _openDepartment(dept),
    );
  }

  Widget _buildToolbar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Søk avdeling, beskrivelse eller leder…',
              prefixIcon: const Icon(AppIcons.search),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _search = ''),
                    ),
              filled: true,
              fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
                ),
              ),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('Alle', _DepartmentFilter.all),
                _filterChip('Mangler leder', _DepartmentFilter.needsLeader),
                _filterChip('Med ansatte', _DepartmentFilter.hasMembers),
                _filterChip('Tomme', _DepartmentFilter.empty),
                const SizedBox(width: 8),
                PopupMenuButton<_DepartmentSort>(
                  tooltip: 'Sorter',
                  onSelected: (v) => setState(() => _sort = v),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _DepartmentSort.name,
                      child: Text('Sorter: Navn A–Å'),
                    ),
                    PopupMenuItem(
                      value: _DepartmentSort.membersDesc,
                      child: Text('Sorter: Flest ansatte'),
                    ),
                    PopupMenuItem(
                      value: _DepartmentSort.membersAsc,
                      child: Text('Sorter: Færrest ansatte'),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? DriftProTheme.cardDark : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(AppIcons.sort, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          _sortLabel,
                          style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_visibleDepartments.length} av ${_departments.length} avdelinger',
            style: DriftProTheme.caption,
          ),
        ],
      ),
    );
  }

  String get _sortLabel {
    switch (_sort) {
      case _DepartmentSort.name:
        return 'Navn';
      case _DepartmentSort.membersDesc:
        return 'Flest ansatte';
      case _DepartmentSort.membersAsc:
        return 'Færrest ansatte';
    }
  }

  Widget _filterChip(String label, _DepartmentFilter value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filter = value),
        selectedColor: DriftProTheme.primaryGreen.withValues(alpha: 0.18),
        checkmarkColor: DriftProTheme.primaryGreen,
        labelStyle: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? DriftProTheme.primaryGreen : null,
        ),
      ),
    );
  }

  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.error, size: 48, color: DriftProTheme.error),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Prøv igjen'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.department, size: 72, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Ingen avdelinger ennå',
            style: DriftProTheme.headingMd,
          ),
          const SizedBox(height: 8),
          Text(
            'Opprett avdelinger for å organisere ansatte, ledere og tilganger.',
            style: DriftProTheme.bodySm.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _createNewDepartment,
            icon: const Icon(AppIcons.add),
            label: const Text('Opprett første avdeling'),
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 56, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text('Ingen treff', style: DriftProTheme.headingSm),
          const SizedBox(height: 6),
          Text(
            'Prøv et annet søkeord eller fjern filter.',
            style: DriftProTheme.bodySm.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
