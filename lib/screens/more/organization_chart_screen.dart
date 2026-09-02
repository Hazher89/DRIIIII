import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/driftpro_client.dart';
import '../../core/constants/company_principals.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/department.dart';
import '../../models/user_profile.dart';
import '../../widgets/common/team_equal_controls.dart';
import '../../widgets/driftpro_loading_indicator.dart';
import '../employees/employee_edit_screen.dart';

/// Live organisasjonskart fra avdelinger + ansatte.
/// Superadmin: endre tittel, flytte/legge til/fjerne ansatte direkte.
class OrganizationChartScreen extends StatefulWidget {
  const OrganizationChartScreen({super.key});

  @override
  State<OrganizationChartScreen> createState() =>
      _OrganizationChartScreenState();
}

class _OrganizationChartScreenState extends State<OrganizationChartScreen> {
  bool _loading = true;
  String? _error;
  UserProfile? _me;
  List<Department> _departments = const [];
  List<UserProfile> _people = const [];
  Set<String> _leaderProfileIds = {};
  RealtimeChannel? _channel;
  Timer? _reloadDebounce;
  final _searchCtrl = TextEditingController();
  String _search = '';

  bool get _canManage => SupabaseService.canManageEmployees(_me);

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _search = _searchCtrl.text.trim().toLowerCase());
    });
    _load(showSpinner: true);
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _searchCtrl.dispose();
    _unsubscribe();
    super.dispose();
  }

  void _unsubscribe() {
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      unawaited(SupabaseService.client.removeChannel(ch));
    }
  }

  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _load(showSpinner: false);
    });
  }

  void _subscribeRealtime(String companyId) {
    _unsubscribe();
    _channel = SupabaseService.client
        .channel('org_chart_$companyId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'company_id',
            value: companyId,
          ),
          callback: (_) => _scheduleReload(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'departments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'company_id',
            value: companyId,
          ),
          callback: (_) => _scheduleReload(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'department_leaders',
          callback: (_) => _scheduleReload(),
        )
        .subscribe();
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final me = await SupabaseService.fetchCurrentUserProfile();
      final companyId =
          me?.companyId ?? await SupabaseService.getCurrentCompanyId();
      if (companyId == null) throw StateError('Fant ikke bedrift.');

      final deps =
          await SupabaseService.fetchDepartments(companyId: companyId);
      var people = await SupabaseService.fetchOrganizationChartPeople();
      if (people.isEmpty && SupabaseService.canManageEmployees(me)) {
        people = (await SupabaseService.fetchProfiles(companyId: companyId))
            .where((u) =>
                !u.isPartnerPortalUser &&
                u.isActive &&
                (u.role != UserRole.superadmin ||
                    CompanyPrincipal.isPrincipal(u)))
            .toList();
      }

      // Sikre at Tommy / Nico / Hazher alltid er med (også hvis RPC/filter mister dem).
      if (SupabaseService.canManageEmployees(me)) {
        final all = await SupabaseService.fetchProfiles(companyId: companyId);
        final byId = {for (final p in people) p.id: p};
        for (final p in all) {
          if (!p.isActive || p.isPartnerPortalUser) continue;
          if (CompanyPrincipal.isPrincipal(p)) {
            byId[p.id] = p;
          }
        }
        people = byId.values.toList();
      }

      final leaderIds = <String>{};
      for (final d in deps) {
        leaderIds.addAll(d.leaderIds);
        if (d.leaderId != null) leaderIds.add(d.leaderId!);
      }

      if (!mounted) return;
      setState(() {
        _me = me;
        _departments = deps;
        _people = people;
        _leaderProfileIds = leaderIds;
        _loading = false;
        _error = null;
      });
      _subscribeRealtime(companyId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<UserProfile> get _filteredPeople {
    if (_search.isEmpty) return _people;
    return _people
        .where((p) =>
            p.fullName.toLowerCase().contains(_search) ||
            p.displayTitle.toLowerCase().contains(_search) ||
            (p.employeeNumber ?? '').contains(_search))
        .toList();
  }

  /// Tommy + Nico (samme nivå).
  List<UserProfile> get _owners {
    final list = _filteredPeople.where(CompanyPrincipal.isOwner).toList();
    list.sort((a, b) {
      final pa = CompanyPrincipal.ofProfile(a)?.sortOrder ?? 99;
      final pb = CompanyPrincipal.ofProfile(b)?.sortOrder ?? 99;
      return pa.compareTo(pb);
    });
    return list;
  }

  /// Hazher (under Tommy/Nico).
  List<UserProfile> get _operationsLeaders {
    final list = _filteredPeople.where(CompanyPrincipal.isOperations).toList();
    list.sort((a, b) => a.fullName.compareTo(b.fullName));
    return list;
  }

  /// Avdelingsledere under Hazher (ikke principals).
  List<UserProfile> get _departmentLeaders {
    return _filteredPeople
        .where((p) =>
            !CompanyPrincipal.isPrincipal(p) &&
            (p.role == UserRole.leder ||
                p.role == UserRole.admin ||
                _leaderProfileIds.contains(p.id)))
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
  }

  List<UserProfile> _membersOf(Department dept) {
    return _filteredPeople
        .where((p) =>
            p.departmentId == dept.id &&
            !CompanyPrincipal.isPrincipal(p) &&
            !_leaderProfileIds.contains(p.id) &&
            p.role != UserRole.leder)
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
  }

  List<UserProfile> get _unassigned {
    final deptIds = _departments.map((d) => d.id).toSet();
    final leaderIds = {
      ..._leaderProfileIds,
      ..._departmentLeaders.map((p) => p.id),
    };
    return _filteredPeople
        .where((p) =>
            !CompanyPrincipal.isPrincipal(p) &&
            !leaderIds.contains(p.id) &&
            p.role != UserRole.leder &&
            (p.departmentId == null ||
                p.departmentId!.isEmpty ||
                !deptIds.contains(p.departmentId)))
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
  }

  Future<void> _openEmployee(UserProfile employee) async {
    if (!_canManage) return;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EmployeeEditScreen(
          employee: employee,
          departments: _departments,
          canEditRole: true,
        ),
      ),
    );
    if (ok == true) await _load(showSpinner: false);
  }

  Future<void> _editTitle(UserProfile employee) async {
    if (!_canManage) return;
    final principal = CompanyPrincipal.ofProfile(employee);
    if (principal != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${principal.displayName} har fast tittel: ${principal.title}',
          ),
        ),
      );
      return;
    }
    final title = TextEditingController(text: employee.jobTitle ?? '');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Endre tittel',
                style: DriftProTheme.headingSm.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(employee.fullName, style: DriftProTheme.caption),
              const SizedBox(height: 16),
              TextField(
                controller: title,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Tittel / stilling',
                  hintText: 'f.eks. Lagermedarbeider',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: TeamControlMetrics.height,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Lagre'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: TeamControlMetrics.height,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Avbryt'),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true) return;
    await SupabaseService.updateEmployeeProfile(
      employee.id,
      jobTitle: title.text.trim(),
    );
    await _load(showSpinner: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tittel oppdatert')),
    );
  }

  Future<void> _moveToDepartment(
    UserProfile employee, {
    String? preferredDepartmentId,
  }) async {
    if (!_canManage) return;
    String? selected = preferredDepartmentId ?? employee.departmentId;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Widget deptTile(String? id, String label) {
              final active = selected == id;
              return ListTile(
                leading: Icon(
                  active
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: active ? DriftProTheme.primaryGreen : null,
                ),
                title: Text(label),
                selected: active,
                onTap: () => setLocal(() => selected = id),
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Velg avdeling',
                      style: DriftProTheme.headingSm.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 4),
                    Text(employee.fullName, style: DriftProTheme.caption),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(ctx).height * 0.5,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          deptTile(null, 'Ingen avdeling'),
                          ..._departments.map((d) => deptTile(d.id, d.name)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: TeamControlMetrics.height,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Lagre'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (ok != true) return;
    await SupabaseService.updateProfileDepartment(employee.id, selected);
    await _load(showSpinner: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Avdeling oppdatert')),
    );
  }

  Future<void> _removeFromDepartment(UserProfile employee) async {
    if (!_canManage) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fjern fra avdeling?'),
        content: Text(
          '${employee.fullName} fjernes fra avdelingen i organisasjonskartet. '
          'Profilen slettes ikke.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Fjern'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await SupabaseService.updateProfileDepartment(employee.id, null);
    await _load(showSpinner: false);
  }

  Future<void> _addEmployeeToDepartment(Department dept) async {
    if (!_canManage) return;
    final candidates = _people
        .where((p) => p.departmentId != dept.id)
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingen flere ansatte å legge til')),
      );
      return;
    }

    String query = '';
    final picked = await showModalBottomSheet<UserProfile>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final filtered = query.isEmpty
                ? candidates
                : candidates
                    .where((p) =>
                        p.fullName.toLowerCase().contains(query) ||
                        (p.jobTitle ?? '').toLowerCase().contains(query))
                    .toList();
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(ctx).height * 0.72,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Legg til i ${dept.name}',
                        style: DriftProTheme.headingSm.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Søk ansatt…',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (v) =>
                            setLocal(() => query = v.trim().toLowerCase()),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final p = filtered[i];
                            String? currentDept;
                            for (final d in _departments) {
                              if (d.id == p.departmentId) {
                                currentDept = d.name;
                                break;
                              }
                            }
                            return ListTile(
                              title: Text(p.fullName),
                              subtitle: Text(
                                [
                                  if ((p.jobTitle ?? '').isNotEmpty) p.jobTitle!,
                                  if (currentDept != null) currentDept,
                                ].join(' · '),
                              ),
                              trailing: const Icon(Icons.add_circle_outline),
                              onTap: () => Navigator.pop(ctx, p),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (picked == null) return;
    await SupabaseService.updateProfileDepartment(picked.id, dept.id);
    await _load(showSpinner: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${picked.fullName} lagt til i ${dept.name}')),
    );
  }

  Future<void> _confirmDeactivate(UserProfile employee) async {
    if (!_canManage) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deaktiver ansatt?'),
        content: Text(
          '${employee.fullName} fjernes fra organisasjonskartet og mister tilgang.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deaktiver'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await SupabaseService.deactivateEmployeeProfile(employee.id);
    await _load(showSpinner: false);
  }

  void _showPersonActions(UserProfile person, {Department? inDepartment}) {
    if (!_canManage) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(person.fullName, style: DriftProTheme.labelLg),
                Text(
                  person.displayTitle,
                  style: DriftProTheme.caption,
                ),
                const SizedBox(height: 12),
                _actionBtn(
                  icon: Icons.badge_outlined,
                  label: CompanyPrincipal.isPrincipal(person)
                      ? 'Fast tittel (${person.displayTitle})'
                      : 'Endre tittel',
                  onTap: () {
                    Navigator.pop(ctx);
                    _editTitle(person);
                  },
                ),
                const SizedBox(height: 8),
                _actionBtn(
                  icon: Icons.apartment_outlined,
                  label: 'Bytt avdeling',
                  onTap: () {
                    Navigator.pop(ctx);
                    _moveToDepartment(person);
                  },
                ),
                if (inDepartment != null) ...[
                  const SizedBox(height: 8),
                  _actionBtn(
                    icon: Icons.person_remove_outlined,
                    label: 'Fjern fra ${inDepartment.name}',
                    onTap: () {
                      Navigator.pop(ctx);
                      _removeFromDepartment(person);
                    },
                  ),
                ],
                const SizedBox(height: 8),
                _actionBtn(
                  icon: Icons.open_in_new,
                  label: 'Åpne full profil',
                  onTap: () {
                    Navigator.pop(ctx);
                    _openEmployee(person);
                  },
                ),
                const SizedBox(height: 8),
                _actionBtn(
                  icon: Icons.person_off_outlined,
                  label: 'Deaktiver ansatt',
                  danger: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDeactivate(person);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return SizedBox(
      height: TeamControlMetrics.height,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20, color: danger ? Colors.red : null),
        label: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: danger ? Colors.red : null,
          ),
        ),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          foregroundColor: danger ? Colors.red : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const DriftProLoadingPage();
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Organisasjonskart')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _load(showSpinner: true),
                  child: const Text('Prøv igjen'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final owners = _owners;
    final operations = _operationsLeaders;
    final deptLeaders = _departmentLeaders;
    final unassigned = _unassigned;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Organisasjonskart'),
        actions: [
          IconButton(
            tooltip: 'Oppdater',
            onPressed: () => _load(showSpinner: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(showSpinner: false),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth;
            final contentW = maxW >= 1100
                ? 980.0
                : maxW >= 800
                    ? 760.0
                    : maxW;
            final padH = maxW > contentW ? (maxW - contentW) / 2 : 16.0;
            final deptCols = maxW >= 1000
                ? 3
                : maxW >= 640
                    ? 2
                    : 1;
            final personCols = maxW >= 900
                ? 3
                : maxW >= 520
                    ? 2
                    : 1;
            final ownerCols = owners.length >= 2
                ? (maxW >= 520 ? 2 : 1)
                : 1;

            return ListView(
              padding: EdgeInsets.fromLTRB(
                padH,
                16,
                padH,
                DriftProClient.isMobile ? 96 : 32,
              ),
              children: [
                Text(
                  'ORGANISASJONSKART',
                  textAlign: TextAlign.center,
                  style: DriftProTheme.headingSm.copyWith(
                    letterSpacing: 3,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _canManage
                      ? 'Live oversikt · trykk en person for å endre'
                      : 'Live oversikt over ledelse og avdelinger',
                  textAlign: TextAlign.center,
                  style: DriftProTheme.caption,
                ),
                const SizedBox(height: 14),
                TeamEqualSearchField(
                  controller: _searchCtrl,
                  hintText: 'Søk navn eller tittel…',
                ),
                const SizedBox(height: 20),
                _sectionLabel('MEDEIERE / DAGLIG LEDELSE'),
                const SizedBox(height: 10),
                if (owners.isEmpty)
                  _emptyHint('Tommy og Nico mangler i katalogen')
                else
                  _personGrid(
                    people: owners,
                    columns: ownerCols,
                    isDark: isDark,
                    highlightLeaders: true,
                  ),
                const SizedBox(height: 12),
                const Center(
                  child: Icon(Icons.arrow_downward_rounded, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                _sectionLabel('DRIFTSLEDER'),
                const SizedBox(height: 10),
                if (operations.isEmpty)
                  _emptyHint('Hazher mangler i katalogen')
                else
                  _personGrid(
                    people: operations,
                    columns: 1,
                    isDark: isDark,
                    highlightLeaders: true,
                  ),
                if (deptLeaders.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Center(
                    child:
                        Icon(Icons.arrow_downward_rounded, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  _sectionLabel('AVDELINGSLEDERE'),
                  const SizedBox(height: 10),
                  _personGrid(
                    people: deptLeaders,
                    columns: personCols,
                    isDark: isDark,
                    highlightLeaders: true,
                  ),
                ],
                const SizedBox(height: 24),
                _sectionLabel('AVDELINGER (${_departments.length})'),
                const SizedBox(height: 10),
                if (_departments.isEmpty)
                  _emptyHint('Ingen avdelinger ennå')
                else
                  _departmentGrid(
                    columns: deptCols,
                    isDark: isDark,
                  ),
                if (unassigned.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _sectionLabel('UTEN AVDELING (${unassigned.length})'),
                  const SizedBox(height: 10),
                  _personGrid(
                    people: unassigned,
                    columns: personCols,
                    isDark: isDark,
                    highlightLeaders: false,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: DriftProTheme.labelSm.copyWith(
        color: Colors.grey,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _emptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: DriftProTheme.caption,
      ),
    );
  }

  Widget _personGrid({
    required List<UserProfile> people,
    required int columns,
    required bool isDark,
    required bool highlightLeaders,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final gap = 10.0;
        final w = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: people.map((p) {
            final isLead = highlightLeaders &&
                (_leaderProfileIds.contains(p.id) ||
                    p.role == UserRole.admin ||
                    p.role == UserRole.leder);
            return SizedBox(
              width: w,
              child: _PersonCard(
                person: p,
                isDark: isDark,
                highlight: isLead || CompanyPrincipal.isPrincipal(p),
                canManage: _canManage,
                onTap: _canManage ? () => _showPersonActions(p) : null,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _departmentGrid({required int columns, required bool isDark}) {
    return LayoutBuilder(
      builder: (context, c) {
        final gap = 12.0;
        final w = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: _departments.map((dept) {
            final members = _membersOf(dept);
            return SizedBox(
              width: w,
              child: _DepartmentCard(
                department: dept,
                members: members,
                isDark: isDark,
                canManage: _canManage,
                isLeader: (p) =>
                    dept.leaderIds.contains(p.id) || dept.leaderId == p.id,
                onAdd: () => _addEmployeeToDepartment(dept),
                onPersonTap: (p) => _showPersonActions(p, inDepartment: dept),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.person,
    required this.isDark,
    required this.highlight,
    required this.canManage,
    this.onTap,
  });

  final UserProfile person;
  final bool isDark;
  final bool highlight;
  final bool canManage;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final border = highlight
        ? const Color(0xFF3B82F6)
        : (isDark ? DriftProTheme.dividerDark : Colors.grey.shade300);

    return Material(
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: border,
              width: highlight ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                    child: Text(
                      person.initials,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: DriftProTheme.primaryGreen,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (canManage)
                    Icon(
                      Icons.more_horiz,
                      size: 18,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                person.fullName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DriftProTheme.labelMd.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                person.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DriftProTheme.caption.copyWith(height: 1.25),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DepartmentCard extends StatelessWidget {
  const _DepartmentCard({
    required this.department,
    required this.members,
    required this.isDark,
    required this.canManage,
    required this.isLeader,
    required this.onAdd,
    required this.onPersonTap,
  });

  final Department department;
  final List<UserProfile> members;
  final bool isDark;
  final bool canManage;
  final bool Function(UserProfile) isLeader;
  final VoidCallback onAdd;
  final void Function(UserProfile) onPersonTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
        ),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  department.name.toUpperCase(),
                  style: DriftProTheme.labelSm.copyWith(
                    color: const Color(0xFF1D4ED8),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              Text(
                '${members.length}',
                style: DriftProTheme.caption.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (members.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Ingen ansatte i avdelingen',
                style: DriftProTheme.caption,
              ),
            )
          else
            ...members.map((p) {
              final lead = isLeader(p);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: lead
                      ? const Color(0xFF3B82F6).withValues(alpha: 0.06)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: canManage ? () => onPersonTap(p) : null,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.fullName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    if (lead) 'Avdelingsleder',
                                    p.displayTitle,
                                  ].where((s) => s.isNotEmpty).toSet().join(' · '),
                                  style: DriftProTheme.caption,
                                ),
                              ],
                            ),
                          ),
                          if (canManage)
                            const Icon(Icons.chevron_right, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          if (canManage) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: TeamControlMetrics.height,
              child: OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Legg til'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DriftProTheme.primaryGreen,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
