import 'package:flutter/material.dart';

import '../../core/services/supabase_service.dart';
import '../../models/user_profile.dart';
import 'employee_hub_screen.dart';
import 'widgets/employee_display.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Ansatte – kun superadmin får full administrasjon.
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  bool _checking = true;
  bool _isSuperAdmin = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final me = await SupabaseService.fetchCurrentUserProfile();
    if (mounted) {
      setState(() {
        _isSuperAdmin = SupabaseService.canManageEmployees(me);
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: const DriftProLoadingCenter(),
      );
    }
    if (_isSuperAdmin) {
      return const EmployeeHubScreen();
    }
    return const _EmployeeScopedReadOnlyList();
  }
}

/// Leder ser kun ansatte i egne avdelinger. Ansatte ser kun seg selv.
class _EmployeeScopedReadOnlyList extends StatefulWidget {
  const _EmployeeScopedReadOnlyList();

  @override
  State<_EmployeeScopedReadOnlyList> createState() => _EmployeeScopedReadOnlyListState();
}

class _EmployeeScopedReadOnlyListState extends State<_EmployeeScopedReadOnlyList> {
  var _loading = true;
  List<UserProfile> _profiles = [];
  UserProfile? _me;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = await SupabaseService.fetchCurrentUserProfile();
    if (me == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final list = await SupabaseService.fetchScopedProfiles(me);
    if (mounted) {
      setState(() {
        _me = me;
        _profiles = list.where((p) => !p.isPartnerPortalUser).toList();
        _loading = false;
      });
    }
  }

  String get _scopeHint {
    if (_me == null) return '';
    if (_me!.role == UserRole.leder) {
      return 'Du ser kun ansatte i avdelingene du leder.';
    }
    return 'Du ser kun din egen profil.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ansatte')),
      body: _loading
          ? const DriftProLoadingCenter()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_scopeHint.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      _scopeHint,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _profiles.length,
                    itemBuilder: (_, i) {
                      final p = _profiles[i];
                      return ListTile(
                        leading: CircleAvatar(child: Text(p.initials)),
                        title: EmployeeDisplay.nameWithNumber(p, emphasizeNumber: true),
                        subtitle: Text(
                          '${p.jobTitle ?? p.role.name}${p.id == _me?.id ? ' · deg' : ''}',
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
