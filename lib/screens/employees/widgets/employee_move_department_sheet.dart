import 'package:flutter/material.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/department.dart';
import '../../../models/user_profile.dart';

/// Flytt ansatt til annen avdeling.
Future<bool?> showEmployeeMoveDepartmentSheet(
  BuildContext context, {
  required UserProfile employee,
  required List<Department> departments,
}) async {
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return _MoveDepartmentBody(
        employee: employee,
        departments: departments,
      );
    },
  );
}

class _MoveDepartmentBody extends StatelessWidget {
  final UserProfile employee;
  final List<Department> departments;

  const _MoveDepartmentBody({
    required this.employee,
    required this.departments,
  });

  String? _currentName() {
    final id = employee.departmentId;
    if (id == null) return null;
    for (final d in departments) {
      if (d.id == id) return d.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentName();
    final sorted = List<Department>.from(departments)
      ..sort((a, b) => a.name.compareTo(b.name));

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              'Flytt ${employee.fullName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          if (employee.employeeNumber != null && employee.employeeNumber!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Ansattnr. ${employee.employeeNumber}',
                style: TextStyle(color: DriftProTheme.primaryGreen, fontWeight: FontWeight.w600),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Text(
              current != null ? 'Nåværende avdeling: $current' : 'Ingen avdeling valgt',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.person_off_outlined),
                  title: const Text('Ingen avdeling'),
                  onTap: () => _move(context, null),
                ),
                ...sorted.map(
                  (d) => ListTile(
                    leading: Icon(
                      Icons.apartment,
                      color: employee.departmentId == d.id
                          ? DriftProTheme.primaryGreen
                          : null,
                    ),
                    title: Text(d.name),
                    trailing: employee.departmentId == d.id
                        ? const Icon(Icons.check, color: DriftProTheme.primaryGreen)
                        : null,
                    onTap: employee.departmentId == d.id
                        ? null
                        : () => _move(context, d.id),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _move(BuildContext context, String? departmentId) async {
    try {
      await SupabaseService.updateProfileDepartment(employee.id, departmentId);
      if (context.mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Avdeling oppdatert')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
