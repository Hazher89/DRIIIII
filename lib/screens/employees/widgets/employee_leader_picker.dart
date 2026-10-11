import 'package:flutter/material.dart';

import '../../../core/constants/company_principals.dart';
import '../../../core/permissions/leadership_chain.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_profile.dart';

/// Superadmin velger nærmeste leder. Tomt valg følger pyramiden.
class EmployeeLeaderPicker extends StatefulWidget {
  const EmployeeLeaderPicker({super.key, required this.employee});

  final UserProfile employee;

  @override
  State<EmployeeLeaderPicker> createState() => _EmployeeLeaderPickerState();
}

class _EmployeeLeaderPickerState extends State<EmployeeLeaderPicker> {
  List<UserProfile> _people = [];
  String? _reportsTo;
  String? _automaticName;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reportsTo = widget.employee.reportsTo;
    _load();
  }

  Future<void> _load() async {
    final companyId = widget.employee.companyId;
    if (companyId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final people = await SupabaseService.fetchProfiles(companyId: companyId);
      final options = await SupabaseService.fetchTicketAssigneeOptions(
        companyId: companyId,
        departmentId: widget.employee.departmentId,
        subjectProfileId: widget.employee.id,
      );
      final automatic = LeadershipChain.directManagers(
        subject: widget.employee,
        options: options,
        honorOverride: false,
      );
      people.sort((a, b) {
        final pa = CompanyPrincipal.ofProfile(a)?.sortOrder ?? 50;
        final pb = CompanyPrincipal.ofProfile(b)?.sortOrder ?? 50;
        final byTier = pa.compareTo(pb);
        if (byTier != 0) return byTier;
        return a.fullName.compareTo(b.fullName);
      });
      if (!mounted) return;
      setState(() {
        _people = people.where((p) => p.id != widget.employee.id && p.isActive).toList();
        _automaticName = automatic.map((p) => p.fullName).join(', ');
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(String? id) async {
    setState(() {
      _reportsTo = id;
      _saving = true;
    });
    try {
      await SupabaseService.setProfileReportsTo(
        profileId: widget.employee.id,
        reportsTo: id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leder er lagret')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke lagre leder: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }

    final known = _reportsTo == null || _people.any((p) => p.id == _reportsTo);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Nærmeste leder', style: DriftProTheme.headingSm),
        const SizedBox(height: 6),
        Text(
          'Automatisk: ansatte går til avdelingsleder, avdelingsleder til Hazher '
          '(driftsleder), og Hazher til Tommy (daglig leder).',
          style: DriftProTheme.caption.copyWith(height: 1.35),
        ),
        if ((_automaticName ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Automatisk leder nå: $_automaticName',
            style: DriftProTheme.caption,
          ),
        ],
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          value: known ? _reportsTo : null,
          decoration: const InputDecoration(
            labelText: 'Leder',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Automatisk (pyramiden)'),
            ),
            ..._people.map(
              (p) => DropdownMenuItem<String?>(
                value: p.id,
                child: Text('${p.fullName} · ${p.displayTitle}'),
              ),
            ),
          ],
          onChanged: _saving ? null : (value) => _save(value),
        ),
      ],
    );
  }
}
