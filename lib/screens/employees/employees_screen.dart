import 'package:flutter/material.dart';

import '../../core/permissions/user_access.dart';
import '../../core/services/supabase_service.dart';
import '../../models/department.dart';
import '../../models/user_profile.dart';
import 'employee_edit_screen.dart';
import 'employee_hub_screen.dart';
import 'widgets/employee_display.dart';
import 'widgets/employee_move_department_sheet.dart';

/// Ansatte – superadmin sendes til full tilgangsstyring.
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
        _isSuperAdmin = me?.isSuperAdmin == true ||
            me?.isAdmin == true ||
            me?.access.canEditEmployees == true;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_isSuperAdmin) {
      return const EmployeeHubScreen();
    }
    return const _EmployeeReadOnlyList();
  }
}

/// Enkel liste for ikke-superadmin med kun lesetilgang.
class _EmployeeReadOnlyList extends StatefulWidget {
  const _EmployeeReadOnlyList();

  @override
  State<_EmployeeReadOnlyList> createState() => _EmployeeReadOnlyListState();
}

class _EmployeeReadOnlyListState extends State<_EmployeeReadOnlyList> {
  var _loading = true;
  List<UserProfile> _profiles = [];
  List<Department> _departments = [];
  bool _canEdit = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = await SupabaseService.fetchCurrentUserProfile();
    final companyId = await SupabaseService.getCurrentCompanyId();
    if (companyId != null) {
      final list = await SupabaseService.fetchProfiles(companyId: companyId);
      final depts = await SupabaseService.fetchDepartments(companyId: companyId);
      if (mounted) {
        setState(() {
          _profiles = list.where((p) => !p.isPartnerPortalUser).toList();
          _departments = depts;
          _canEdit = me?.access.canEditEmployees == true ||
              me?.isSuperAdmin == true ||
              me?.role == UserRole.leder;
          _loading = false;
        });
      }
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _openEdit(UserProfile p) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeEditScreen(
          employee: p,
          departments: _departments,
        ),
      ),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ansatte'),
        actions: [
          if (_canEdit)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: Text('Trykk ✏️ for å redigere', style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _profiles.length,
              itemBuilder: (_, i) {
                final p = _profiles[i];
                return ListTile(
                  leading: CircleAvatar(child: Text(p.initials)),
                  title: EmployeeDisplay.nameWithNumber(p, emphasizeNumber: true),
                  subtitle: Text(
                    '${p.role.name} · ${p.email}${p.phone != null ? " · ${p.phone}" : ""}',
                  ),
                  trailing: _canEdit
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.swap_horiz),
                              tooltip: 'Flytt avdeling',
                              onPressed: () async {
                                final ok = await showEmployeeMoveDepartmentSheet(
                                  context,
                                  employee: p,
                                  departments: _departments,
                                );
                                if (ok == true) _load();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Rediger telefon og personinfo',
                              onPressed: () => _openEdit(p),
                            ),
                          ],
                        )
                      : null,
                  onTap: _canEdit ? () => _openEdit(p) : null,
                );
              },
            ),
    );
  }
}
