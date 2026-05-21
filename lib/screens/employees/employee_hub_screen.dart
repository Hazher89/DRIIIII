import 'package:flutter/material.dart';

import '../../core/permissions/access_catalog.dart';
import '../../core/permissions/user_access.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/department.dart';
import '../../models/user_profile.dart';
import '../admin/company_sms_settings_screen.dart';
import 'employee_access_detail_screen.dart';
import 'employee_edit_screen.dart';
import 'widgets/employee_approval_sheet.dart';

/// Ansattadministrasjon – superadmin styrer alle DriftPro-tilganger per bruker.
class EmployeeHubScreen extends StatefulWidget {
  const EmployeeHubScreen({super.key});

  @override
  State<EmployeeHubScreen> createState() => _EmployeeHubScreenState();
}

class _EmployeeHubScreenState extends State<EmployeeHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = true;
  String? _error;
  List<UserProfile> _all = [];
  List<Department> _departments = [];
  UserProfile? _me;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final me = await SupabaseService.fetchCurrentUserProfile();
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId == null && me?.isSuperAdmin != true) {
        throw StateError('Ingen bedrift');
      }
      // Superadmin skal se alle interne ansatte (uavhengig av company_id-filter).
      final users = me?.isSuperAdmin == true
          ? await SupabaseService.fetchProfiles()
          : await SupabaseService.fetchProfiles(companyId: companyId);
      final depts = await SupabaseService.fetchDepartments(companyId: companyId);
      if (!mounted) return;
      setState(() {
        _me = me;
        _all = users.where((u) => !u.isPartnerPortalUser).toList();
        _departments = depts;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  bool get _isSuperAdmin => _me?.isSuperAdmin == true;

  bool get _canEditEmployees =>
      _isSuperAdmin || (_me?.access.canEditEmployees == true);

  bool get _canSmsSettings =>
      _isSuperAdmin ||
      _me?.role == UserRole.admin ||
      _me?.role == UserRole.leder;

  List<UserProfile> get _pending =>
      _all.where((u) => u.isOnboarded && !u.isApproved).toList();

  List<UserProfile> get _visible {
    if (_search.isEmpty) return _all;
    final q = _search.toLowerCase();
    return _all
        .where((u) =>
            u.fullName.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q) ||
            (u.phone ?? '').contains(q))
        .toList();
  }

  String _deptName(String? id) {
    if (id == null) return '—';
    for (final d in _departments) {
      if (d.id == id) return d.name;
    }
    return 'Ukjent';
  }

  Future<void> _deleteEmployee(UserProfile user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett ansatt permanent?'),
        content: Text(
          '«${user.fullName}» fjernes fra auth og hele systemet. '
          'Handlingen kan ikke angres.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Slett permanent'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await SupabaseService.deleteUserPermanently(user.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.fullName} ble slettet')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sletting feilet: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _openEmployee(UserProfile user) async {
    if (!user.isApproved) {
      await _approve(user);
      return;
    }

    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeAccessDetailScreen(
          employee: user,
          departments: _departments,
          isSuperAdmin: _isSuperAdmin,
          canEditProfile: _canEditEmployees,
          onSaved: _load,
        ),
      ),
    );
    if (ok == true) await _load();
  }

  Future<void> _approve(UserProfile user) async {
    final ok = await EmployeeApprovalSheet.show(
      context,
      user: user,
      departments: _departments,
      onApprove: ({required role, required departmentId, required accessSettings}) =>
          SupabaseService.approveEmployee(
        profileId: user.id,
        role: role,
        departmentId: departmentId,
        accessSettings: accessSettings,
        setDepartmentLeader: role == UserRole.leder,
      ),
    );
    if (ok == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Ansatte & tilganger'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: 'Alle (${_all.length})'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Venter godkjenning'),
                  if (_pending.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: DriftProTheme.error,
                      child: Text(
                        '${_pending.length}',
                        style: const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_canSmsSettings)
            IconButton(
              icon: const Icon(Icons.sms_outlined),
              tooltip: 'SMS-innstillinger (Mavi)',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CompanySmsSettingsScreen(),
                ),
              ),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _infoBanner(isDark),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Søk navn, e-post, telefon…',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          _employeeList(_visible, isDark),
                          _employeeList(_pending, isDark, pending: true),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _infoBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: DriftProTheme.primaryGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.admin_panel_settings, color: Colors.white, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isSuperAdmin
                      ? 'Superadmin – alle moduler'
                      : 'Ansattoversikt (lesetilgang)',
                  style: DriftProTheme.labelLg.copyWith(color: Colors.white),
                ),
                Text(
                  _isSuperAdmin
                      ? 'Trykk på ansatt for tilganger. Bruk ✏️ for telefon, adresse og datoer.'
                      : _canEditEmployees
                          ? 'Trykk for tilganger – eller ✏️ for å redigere telefon og personinfo.'
                          : 'Kun lesetilgang.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _employeeList(
    List<UserProfile> list,
    bool isDark, {
    bool pending = false,
  }) {
    if (list.isEmpty) {
      return Center(
        child: Text(
          pending
              ? 'Ingen venter på godkjenning'
              : 'Ingen ansatte funnet',
          style: DriftProTheme.bodyMd.copyWith(color: Colors.grey),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _tile(list[i], isDark, pending: pending),
    );
  }

  Widget _tile(UserProfile user, bool isDark, {bool pending = false}) {
    final settings = AccessCatalog.normalize(user.accessSettings, user.role);
    final enabled = AccessCatalog.countEnabled(settings);

    return Material(
      color: pending
          ? Colors.orange.withValues(alpha: 0.1)
          : (isDark ? DriftProTheme.cardDark : Colors.white),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openEmployee(user),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                child: Text(user.initials, style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    Text(user.email, style: DriftProTheme.caption),
                    const SizedBox(height: 4),
                    Text(
                      '${user.role.name} · ${_deptName(user.departmentId)} · $enabled tilganger aktive',
                      style: DriftProTheme.caption,
                    ),
                  ],
                ),
              ),
              if (pending)
                FilledButton(
                  onPressed: () => _approve(user),
                  child: const Text('Godkjenn'),
                )
              else ...[
                if (_canEditEmployees)
                  IconButton(
                    tooltip: 'Rediger telefon, adresse, dato',
                    icon: const Icon(Icons.edit_outlined,
                        color: DriftProTheme.primaryGreen),
                    onPressed: () async {
                      final ok = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EmployeeEditScreen(
                            employee: user,
                            departments: _departments,
                            canEditRole: _isSuperAdmin,
                          ),
                        ),
                      );
                      if (ok == true) await _load();
                    },
                  ),
                if (_isSuperAdmin &&
                    user.role != UserRole.superadmin &&
                    user.id != _me?.id)
                  IconButton(
                    tooltip: 'Slett ansatt permanent',
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _deleteEmployee(user),
                  ),
                const Icon(Icons.chevron_right),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
