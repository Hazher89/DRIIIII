import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';
import '../../../models/ticket.dart';
import '../../../models/user_profile.dart';
import '../../../core/permissions/permission_gate.dart';
import 'dashboard_command_palette.dart';

class DashboardSearchBar extends StatelessWidget {
  final UserProfile? profile;
  final List<Ticket> scopedTickets;
  final List<Absence> scopedAbsences;
  final NavigateByAccess? onNavigateByAccess;

  const DashboardSearchBar({
    super.key,
    required this.profile,
    required this.scopedTickets,
    required this.scopedAbsences,
    this.onNavigateByAccess,
  });

  void _open(BuildContext context) {
    if (profile == null) return;
    DashboardCommandPalette.show(
      context,
      profile: profile!,
      scopedTickets: scopedTickets,
      scopedAbsences: scopedAbsences,
      onNavigateByAccess: onNavigateByAccess,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        child: InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
              ),
              boxShadow: DriftProTheme.cardShadow,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: DriftProTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.search_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Søk i systemet',
                    style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '⌘K',
                    style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
