import 'package:flutter/material.dart';

import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/department.dart';
import '../../models/user_profile.dart';
import '../employees/employee_edit_screen.dart';

class OrganizationChartScreen extends StatefulWidget {
  const OrganizationChartScreen({super.key});

  @override
  State<OrganizationChartScreen> createState() => _OrganizationChartScreenState();
}

class _OrganizationChartScreenState extends State<OrganizationChartScreen> {
  bool _loading = true;
  String? _error;
  UserProfile? _me;
  List<Department> _departments = const [];
  List<UserProfile> _profiles = const [];

  bool get _canEdit => _me?.isAdmin == true || _me?.role == UserRole.leder;

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
      final me = await SupabaseService.fetchCurrentUserProfile();
      final companyId = me?.companyId ?? await SupabaseService.getCurrentCompanyId();
      if (companyId == null) throw StateError('Fant ikke bedrift.');

      await _ensureHatamEmployee(companyId);

      final deps = await SupabaseService.fetchDepartments(companyId: companyId);
      final users = await SupabaseService.fetchProfiles(companyId: companyId);
      if (!mounted) return;
      setState(() {
        _me = me;
        _departments = deps;
        _profiles = users.where((u) => !u.isPartnerPortalUser && u.isActive).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _ensureHatamEmployee(String companyId) async {
    final users = await SupabaseService.fetchProfiles(companyId: companyId);
    final exists = users.any((u) => u.fullName.trim().toLowerCase() == 'hatam rasoulpour');
    if (exists) return;
    try {
      await SupabaseService.createEmployeeProfile(
        companyId: companyId,
        fullName: 'Hatam Rasoulpour',
        jobTitle: 'Lagermedarbeider',
        role: UserRole.ansatt,
      );
    } catch (_) {}
  }

  Future<void> _openEmployee(UserProfile employee) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EmployeeEditScreen(
          employee: employee,
          departments: _departments,
          canEditRole: _me?.isAdmin == true,
        ),
      ),
    );
    if (ok == true) _load();
  }

  Future<void> _editQuick(UserProfile employee) async {
    final name = TextEditingController(text: employee.fullName);
    final title = TextEditingController(text: employee.jobTitle ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rediger ansatt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Navn')),
            const SizedBox(height: 10),
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Tittel')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lagre')),
        ],
      ),
    );
    if (ok != true) return;
    await SupabaseService.updateEmployeeProfile(
      employee.id,
      fullName: name.text.trim(),
      jobTitle: title.text.trim(),
    );
    await _load();
  }

  Future<void> _deleteEmployee(UserProfile employee) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett ansatt?'),
        content: Text('Vil du slette ${employee.fullName} permanent?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final canHardDelete =
          _me?.role == UserRole.superadmin || _me?.role == UserRole.admin;
      if (canHardDelete) {
        if (!mounted) return;
        final hard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Permanent sletting?'),
            content: Text(
              'Vil du slette ${employee.fullName} permanent fra systemet '
              '(auth + profil)? Dette kan ikke angres.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Kun deaktiver'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Slett permanent'),
              ),
            ],
          ),
        );
        if (hard == true) {
          await SupabaseService.deleteUserPermanently(employee.id);
        } else {
          await SupabaseService.deactivateEmployeeProfile(employee.id);
        }
      } else {
        await SupabaseService.deactivateEmployeeProfile(employee.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ansatt fjernet fra organisasjonskartet.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke fjerne ansatt: $e')),
      );
    }
    await _load();
  }

  Future<void> _addEmployee(Department d) async {
    final name = TextEditingController();
    final title = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Legg til ansatt i ${d.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Navn *')),
            const SizedBox(height: 10),
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Tittel')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, name.text.trim().isNotEmpty), child: const Text('Opprett')),
        ],
      ),
    );
    if (ok != true || _me?.companyId == null) return;
    await SupabaseService.createEmployeeProfile(
      companyId: _me!.companyId!,
      fullName: name.text.trim(),
      departmentId: d.id,
      jobTitle: title.text.trim().isEmpty ? null : title.text.trim(),
    );
    await _load();
  }

  bool _isBilparkUnderIngrid(Department d) {
    final depName = d.name.toLowerCase();
    if (!depName.contains('bilpark')) return false;
    final leaderIds = d.leaderIds.toSet();
    final leader = _profiles.where((p) => leaderIds.contains(p.id)).toList();
    return leader.any((l) => l.fullName.toLowerCase().contains('ingrid hoem'));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Organisasjonskart')),
        body: Center(child: Text(_error!)),
      );
    }

    final board = _profiles.where((p) => p.role == UserRole.superadmin || p.role == UserRole.admin).toList();
    final deptCards = _departments.where((d) => !_isBilparkUnderIngrid(d)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Organisasjonskart'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'ORGANISASJONSKART',
            textAlign: TextAlign.center,
            style: DriftProTheme.headingSm.copyWith(letterSpacing: 4),
          ),
          const SizedBox(height: 12),
          if (board.isNotEmpty) ...[
            Text('STYRET', textAlign: TextAlign.center, style: DriftProTheme.labelSm.copyWith(color: Colors.grey)),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: board.map((u) => _personCard(u, highlight: true)).toList(),
            ),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: deptCards.map(_departmentCard).toList(),
          ),
        ],
      ),
    );
  }

  Widget _departmentCard(Department d) {
    final members = _profiles.where((p) => p.departmentId == d.id).toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    final leaderIds = d.leaderIds.toSet();
    final leaders = members.where((m) => leaderIds.contains(m.id) || m.role == UserRole.leder).toList();
    final others = members.where((m) => !leaders.contains(m)).toList();

    return Container(
      width: 360,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(d.name.toUpperCase(), style: DriftProTheme.labelSm.copyWith(color: const Color(0xFF1D4ED8)))),
              if (_canEdit)
                IconButton(
                  onPressed: () => _addEmployee(d),
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  tooltip: 'Legg til ansatt',
                ),
            ],
          ),
          if (leaders.isNotEmpty) ...leaders.map((l) => _employeeRow(l)),
          if (others.isNotEmpty && leaders.isNotEmpty) const Divider(),
          ...others.map((o) => _employeeRow(o)),
          if (members.isEmpty)
            Text('Ingen ansatte', style: DriftProTheme.caption),
        ],
      ),
    );
  }

  Widget _personCard(UserProfile u, {bool highlight = false}) {
    return InkWell(
      onTap: () => _openEmployee(u),
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: highlight ? const Color(0xFF3B82F6) : Colors.grey.shade200, width: highlight ? 1.5 : 1),
        ),
        child: Column(
          children: [
            Text(u.fullName, style: DriftProTheme.labelLg, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text((u.jobTitle ?? u.role.name).toUpperCase(), style: DriftProTheme.caption, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _employeeRow(UserProfile u) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: () => _openEmployee(u),
      title: Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(u.jobTitle ?? 'Ansatt'),
      trailing: _canEdit
          ? PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') _editQuick(u);
                if (v == 'delete') _deleteEmployee(u);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Rediger navn/tittel')),
                PopupMenuItem(value: 'delete', child: Text('Slett ansatt')),
              ],
            )
          : const Icon(Icons.open_in_new, size: 16),
    );
  }
}
