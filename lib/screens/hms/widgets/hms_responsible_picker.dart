import 'package:flutter/material.dart';

import '../../../core/constants/company_principals.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/ticket_assignee_options.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Velg ansvarlig — kun egen leder + ledelsen (Tommy/Nico/Hazher).
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

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: DriftProLoadingCenter(),
      );
    }

    final nearest = options.nearestLeaders;
    final leadership = options.leadership;
    if (nearest.isEmpty && leadership.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          'Ingen ansvarlige funnet — kontakt din leder eller ledelsen.',
          style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
        ),
      );
    }

    Widget tile(UserProfile p) {
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
            p.displayTitle,
            style: const TextStyle(fontSize: 11),
          ),
          activeColor: DriftProTheme.primaryGreen,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ansvarlig for vurdering', style: DriftProTheme.labelLg),
        const SizedBox(height: 4),
        Text(
          'Kun din leder eller ledelsen (Tommy, Nico, Hazher).',
          style: DriftProTheme.bodySm.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 8),
        if (nearest.isNotEmpty) ...[
          Text(
            'Din leder',
            style: DriftProTheme.labelSm.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          ...nearest.map(tile),
          const SizedBox(height: 8),
        ],
        if (leadership.isNotEmpty) ...[
          Text(
            'Ledelsen',
            style: DriftProTheme.labelSm.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          ...leadership.map(tile),
        ],
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
