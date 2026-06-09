import 'package:flutter/material.dart';

import '../../../core/permissions/user_access.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/time_clock/time_clock_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/department.dart';
import '../../../models/time_clock/time_clock_presence.dart';
import '../../../models/user_profile.dart';
import '../../employees/employee_access_detail_screen.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

class TimeClockPresenceTab extends StatefulWidget {
  const TimeClockPresenceTab({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<TimeClockPresenceTab> createState() => _TimeClockPresenceTabState();
}

class _TimeClockPresenceTabState extends State<TimeClockPresenceTab> {
  List<TimeClockPresence> _all = [];
  List<Department> _departments = [];
  Map<String, UserProfile> _profilesById = {};
  String? _departmentFilter;
  String _search = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final companyId = widget.profile.companyId;
      final depts = await SupabaseService.fetchDepartments(companyId: companyId);
      final presence = await TimeClockService.listPresence(
        departmentId: _departmentFilter,
      );
      final profiles = companyId != null
          ? await SupabaseService.fetchProfiles(companyId: companyId)
          : <UserProfile>[];
      if (!mounted) return;
      setState(() {
        _departments = depts;
        _all = presence;
        _profilesById = {for (final p in profiles) p.id: p};
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Kunne ikke laste oversikt';
        _loading = false;
      });
    }
  }

  List<TimeClockPresence> get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((e) {
      return e.fullName.toLowerCase().contains(q) ||
          (e.employeeNumber ?? '').contains(q);
    }).toList();
  }

  Future<void> _openEmployee(TimeClockPresence presence) async {
    final employee = _profilesById[presence.profileId];
    if (employee == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fant ikke ansattprofil')),
      );
      return;
    }

    final me = widget.profile;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeAccessDetailScreen(
          employee: employee,
          departments: _departments,
          isSuperAdmin: me.isSuperAdmin,
          canEditProfile: me.isSuperAdmin || me.access.canEditEmployees,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const DriftProLoadingPage();

    final clockedIn = TimeClockService.clockedInCount(_all);
    final filtered = _filtered;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        _toolbar(clockedIn, filtered.length, isDark),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(_error!, style: const TextStyle(color: DriftProTheme.error)),
          ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'Ingen ansatte funnet',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) => _employeeTile(filtered[i], isDark),
                ),
        ),
      ],
    );
  }

  Widget _toolbar(int clockedIn, int shown, bool isDark) {
    return Material(
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade300.withValues(alpha: 0.6))),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth > 720;
            final deptField = SizedBox(
              width: wide ? 200 : double.infinity,
              child: DropdownButtonFormField<String?>(
                value: _departmentFilter,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Avdeling',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('- alle -')),
                  ..._departments.map(
                    (d) => DropdownMenuItem(value: d.id, child: Text(d.name)),
                  ),
                ],
                onChanged: (v) {
                  _departmentFilter = v;
                  _load();
                },
              ),
            );
            final searchField = TextField(
              decoration: const InputDecoration(
                labelText: 'Søk ansatt',
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search, size: 20),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) => setState(() => _search = v),
            );
            final stats = Wrap(
              spacing: 16,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _statChip(Icons.people_outline, 'Viser $shown'),
                _statChip(
                  Icons.login_rounded,
                  'Innstemplet: $clockedIn / ${_all.length}',
                  color: DriftProTheme.primaryGreen,
                ),
                IconButton(
                  tooltip: 'Oppdater',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            );

            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  deptField,
                  const SizedBox(width: 12),
                  Expanded(child: searchField),
                  const SizedBox(width: 12),
                  stats,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                deptField,
                const SizedBox(height: 10),
                searchField,
                const SizedBox(height: 10),
                stats,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String label, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color ?? Colors.grey.shade700),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  Widget _employeeTile(TimeClockPresence e, bool isDark) {
    final first = e.firstName ?? (e.fullName.split(' ').isNotEmpty ? e.fullName.split(' ').first : '');
    final last = e.lastName ??
        (e.fullName.split(' ').length > 1 ? e.fullName.split(' ').sublist(1).join(' ') : '');

    return Material(
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openEmployee(e),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  e.employeeNumber ?? '—',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  first,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  last,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 3,
                child: _statusCell(e),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade500, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusCell(TimeClockPresence e) {
    final color = e.isClockedIn ? DriftProTheme.success : Colors.grey;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            e.statusLabel,
            style: TextStyle(
              color: e.isClockedIn ? Colors.green.shade800 : Colors.grey.shade700,
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
