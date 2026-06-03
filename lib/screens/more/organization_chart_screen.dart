import 'package:flutter/material.dart';

import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/department.dart';
import '../../models/user_profile.dart';
import '../employees/employee_edit_screen.dart';

/// Fast visuell struktur — matcher offisielt organisasjonskart (uten superadmin).
class _OrgPerson {
  const _OrgPerson(this.name, this.title, {this.highlight = false});

  final String name;
  final String title;
  final bool highlight;
}

class _OrgTeam {
  const _OrgTeam(this.header, this.members);

  final String header;
  final List<_OrgPerson> members;
}

class OrganizationChartScreen extends StatefulWidget {
  const OrganizationChartScreen({super.key});

  @override
  State<OrganizationChartScreen> createState() => _OrganizationChartScreenState();
}

class _OrganizationChartScreenState extends State<OrganizationChartScreen> {
  static const _styret = [
    _OrgPerson('Tommy Larsen', 'DAGLIG LEDER & FAGLIG LEDER', highlight: true),
    _OrgPerson('Nicola Vino', 'ØKONOMI & ADMINISTRASJON'),
  ];

  static const _driftsleder = _OrgPerson('Hazher Abdullah', 'DRIFTSLEDER', highlight: true);

  static const _ledere = [
    _OrgPerson('Karwan Lian', 'LAGERSJEF & VERNEOMBUD'),
    _OrgPerson('Zelimhan Zavalovitsj', 'RUTEPLANLEGGER'),
    _OrgPerson('Jaspreet Singh', 'KJØRELEDER & TILLITSVALGT'),
  ];

  static const _lagerteam = _OrgTeam('LAGERTEAM', [
    _OrgPerson('Aware Rasoulpour', 'Lagermedarbeider'),
    _OrgPerson('Jamal Farkhapour', 'Lagermedarbeider'),
    _OrgPerson('Madyar Khezernia', 'Lagermedarbeider'),
    _OrgPerson('Aso Ibrahimi', 'Lagermedarbeider'),
    _OrgPerson('Hatam Rasoulpour', 'Lagermedarbeider'),
  ]);

  static const _kjorekontor = _OrgTeam('KJØREKONTOR', [
    _OrgPerson('Ingrid Hoem', 'Assisterende kjøreleder'),
    _OrgPerson('Julie Sayeeda Eyland Pande-Rolfsen', 'Kontor'),
    _OrgPerson('Herish Hameed Alsabaawi', 'Kontor/Brannvern'),
  ]);

  static const _bilpark = _OrgTeam('BILPARK', [
    _OrgPerson('Adam Michta', 'Sjåfør & CALMAN'),
    _OrgPerson('Rafal Dopieralski', 'Service & CALMAN'),
  ]);

  bool _loading = true;
  String? _error;
  UserProfile? _me;
  List<Department> _departments = const [];
  List<UserProfile> _profiles = const [];

  bool get _canManage => SupabaseService.canManageEmployees(_me);

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

      final deps = await SupabaseService.fetchDepartments(companyId: companyId);
      final canManage = SupabaseService.canManageEmployees(me);
      final users = canManage
          ? await SupabaseService.fetchProfiles(companyId: companyId)
          : const <UserProfile>[];
      if (!mounted) return;
      setState(() {
        _me = me;
        _departments = deps;
        _profiles = users
            .where((u) =>
                !u.isPartnerPortalUser &&
                u.isActive &&
                u.role != UserRole.superadmin)
            .toList();
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

  UserProfile? _profileFor(String displayName) {
    if (!_canManage) return null;
    final key = _nameKey(displayName);
    for (final p in _profiles) {
      if (_nameKey(p.fullName) == key) return p;
    }
    for (final p in _profiles) {
      final pk = _nameKey(p.fullName);
      if (pk.contains(key) || key.contains(pk)) return p;
    }
    return null;
  }

  String _nameKey(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-zæøå0-9 ]'), '').trim();

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
    if (ok == true) _load();
  }

  Future<void> _editQuick(UserProfile employee) async {
    if (!_canManage) return;
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
    if (!_canManage) return;
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ansatt fjernet.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke fjerne ansatt: $e')),
      );
    }
    await _load();
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Organisasjonskart'),
        actions: [
          if (_canManage)
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          Text(
            'ORGANISASJONSKART',
            textAlign: TextAlign.center,
            style: DriftProTheme.headingSm.copyWith(letterSpacing: 4),
          ),
          const SizedBox(height: 12),
          Text(
            'STYRET',
            textAlign: TextAlign.center,
            style: DriftProTheme.labelSm.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          _centeredRow(_styret.map(_personCard).toList()),
          const SizedBox(height: 20),
          _centeredRow([_personCard(_driftsleder)]),
          const SizedBox(height: 20),
          _centeredRow(_ledere.map(_personCard).toList()),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _teamBox(_lagerteam)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _teamBox(_kjorekontor)),
                          const SizedBox(width: 12),
                          Expanded(child: _teamBox(_bilpark)),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _teamBox(_lagerteam),
                  const SizedBox(height: 14),
                  _teamBox(_kjorekontor),
                  const SizedBox(height: 14),
                  _teamBox(_bilpark),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _centeredRow(List<Widget> children) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          children[i],
        ],
      ],
    );
  }

  Widget _personCard(_OrgPerson person) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: person.highlight ? const Color(0xFF3B82F6) : Colors.grey.shade300,
          width: person.highlight ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            person.name,
            style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            person.title,
            style: DriftProTheme.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _teamBox(_OrgTeam team) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            team.header,
            style: DriftProTheme.labelSm.copyWith(
              color: const Color(0xFF1D4ED8),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...team.members.map(_teamMemberRow),
        ],
      ),
    );
  }

  Widget _teamMemberRow(_OrgPerson person) {
    final profile = _profileFor(person.name);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(person.title, style: DriftProTheme.caption),
              ],
            ),
          ),
          if (_canManage && profile != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (v) {
                if (v == 'open') _openEmployee(profile);
                if (v == 'edit') _editQuick(profile);
                if (v == 'delete') _deleteEmployee(profile);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'open', child: Text('Åpne profil')),
                PopupMenuItem(value: 'edit', child: Text('Rediger navn/tittel')),
                PopupMenuItem(value: 'delete', child: Text('Slett ansatt')),
              ],
            ),
        ],
      ),
    );
  }
}
