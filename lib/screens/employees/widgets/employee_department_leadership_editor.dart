import 'package:flutter/material.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/department.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Velg hvilke avdelinger en ansatt skal være leder for (kan være flere).
class EmployeeDepartmentLeadershipEditor extends StatefulWidget {
  final UserProfile employee;
  final List<Department> departments;

  const EmployeeDepartmentLeadershipEditor({
    super.key,
    required this.employee,
    required this.departments,
  });

  @override
  State<EmployeeDepartmentLeadershipEditor> createState() =>
      _EmployeeDepartmentLeadershipEditorState();
}

class _EmployeeDepartmentLeadershipEditorState
    extends State<EmployeeDepartmentLeadershipEditor> {
  Set<String> _ledDepartmentIds = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = await SupabaseService.fetchDepartmentIdsLedByProfile(
      widget.employee.id,
    );
    if (mounted) {
      setState(() {
        _ledDepartmentIds = ids;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(String departmentId, bool value) async {
    setState(() => _saving = true);
    try {
      await SupabaseService.setProfileLeadsDepartment(
        departmentId: departmentId,
        profileId: widget.employee.id,
        isLeader: value,
      );
      setState(() {
        if (value) {
          _ledDepartmentIds.add(departmentId);
        } else {
          _ledDepartmentIds.remove(departmentId);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value ? 'Lagt til som avdelingsleder' : 'Fjernet som leder'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: DriftProTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: const DriftProLoadingCenter(),
      );
    }

    final sorted = List<Department>.from(widget.departments)
      ..sort((a, b) => a.name.compareTo(b.name));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Avdelingsleder for',
          style: DriftProTheme.headingSm,
        ),
        const SizedBox(height: 6),
        Text(
          'Velg én eller flere avdelinger ${widget.employee.fullName} skal lede. '
          'Dette er uavhengig av hvilken avdeling personen tilhører som ansatt.',
          style: DriftProTheme.caption.copyWith(height: 1.35),
        ),
        const SizedBox(height: 12),
        if (sorted.isEmpty)
          const Text('Ingen avdelinger opprettet ennå.')
        else
          ...sorted.map((d) {
            final isLed = _ledDepartmentIds.contains(d.id);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: SwitchListTile(
                title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  isLed
                      ? 'Er avdelingsleder — får varsler om fravær m.m.'
                      : 'Ikke leder for denne avdelingen',
                  style: const TextStyle(fontSize: 12),
                ),
                value: isLed,
                activeThumbColor: DriftProTheme.primaryGreen,
                onChanged: _saving ? null : (v) => _toggle(d.id, v),
              ),
            );
          }),
        if (_ledDepartmentIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: _ledDepartmentIds.map((id) {
              final dept = sorted.where((d) => d.id == id).firstOrNull;
              final name = dept?.name ?? 'Avdeling';
              return Chip(
                label: Text('Leder: $name'),
                backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
