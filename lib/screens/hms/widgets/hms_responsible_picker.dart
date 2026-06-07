import 'package:flutter/material.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/ticket_assignee_options.dart';
import '../../../models/user_profile.dart';

/// Velg ansvarlig leder/saksbehandler for ROS eller SJA.
class HmsResponsiblePicker extends StatelessWidget {
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  final TicketAssigneeOptions options;
  final bool loading;

  const HmsResponsiblePicker({
    super.key,
    required this.selectedId,
    required this.onChanged,
    required this.options,
    this.loading = false,
  });

  static String displayName(UserProfile p) {
    var name = p.fullName.trim();
    for (final suffix in [
      ' · Superadmin',
      ' · superadmin',
      ' - Superadmin',
      ' - superadmin',
    ]) {
      if (name.endsWith(suffix)) {
        name = name.substring(0, name.length - suffix.length).trim();
      }
    }
    return name.isEmpty ? p.fullName : name;
  }

  List<UserProfile> get _candidates {
    final seen = <String>{};
    final list = <UserProfile>[];
    for (final p in [
      ...options.nearestLeaders,
      ...options.otherLeaders,
      ...options.superadmins,
    ]) {
      if (seen.add(p.id)) list.add(p);
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final candidates = _candidates;
    if (candidates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          'Ingen ansvarlige funnet — kontakt HR.',
          style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ansvarlig for vurdering', style: DriftProTheme.labelLg),
        const SizedBox(height: 4),
        Text(
          'Valgt person får e-post og SMS med beskjed om å logge inn og vurdere.',
          style: DriftProTheme.bodySm.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 8),
        ...candidates.map((p) {
          final selected = selectedId == p.id;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: selected
                    ? DriftProTheme.primaryGreen
                    : Colors.grey.shade300,
                width: selected ? 2 : 1,
              ),
            ),
            child: RadioListTile<String>(
              value: p.id,
              groupValue: selectedId,
              onChanged: (v) => onChanged(v),
              title: Text(
                displayName(p),
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              subtitle: Text(
                p.role == UserRole.leder ? 'Leder' : 'Administrator',
                style: const TextStyle(fontSize: 11),
              ),
              activeColor: DriftProTheme.primaryGreen,
            ),
          );
        }),
      ],
    );
  }

  static Future<TicketAssigneeOptions> loadOptions() async {
    final companyId = await SupabaseService.getCurrentCompanyId();
    final profile = await SupabaseService.fetchCurrentUserProfile();
    if (companyId == null) return const TicketAssigneeOptions();
    return SupabaseService.fetchTicketAssigneeOptions(
      companyId: companyId,
      departmentId: profile?.departmentId,
    );
  }
}
