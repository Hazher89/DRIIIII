import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/permissions/user_access.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_profile.dart';

class DashboardPersonalSnapshot {
  final int myPendingAbsences;
  final int myOpenTickets;
  final int? vacationDaysLeft;
  final String? departmentName;
  final String dataScopeLabel;
  final String roleLabel;

  const DashboardPersonalSnapshot({
    this.myPendingAbsences = 0,
    this.myOpenTickets = 0,
    this.vacationDaysLeft,
    this.departmentName,
    required this.dataScopeLabel,
    required this.roleLabel,
  });
}

class DashboardPersonalPanel extends StatelessWidget {
  final UserProfile profile;
  final UserAccess access;
  final DashboardPersonalSnapshot snapshot;
  final VoidCallback? onOpenFravaer;
  final VoidCallback? onOpenAvvik;
  final VoidCallback? onOpenProfile;

  const DashboardPersonalPanel({
    super.key,
    required this.profile,
    required this.access,
    required this.snapshot,
    this.onOpenFravaer,
    this.onOpenAvvik,
    this.onOpenProfile,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chips = <Widget>[];

    if (access.canFravaer && snapshot.vacationDaysLeft != null) {
      chips.add(_chip(
        Icons.beach_access_outlined,
        '${snapshot.vacationDaysLeft} feriedager igjen',
        DriftProTheme.absenceVacation,
        onOpenFravaer,
      ));
    }
    if (access.canFravaer && snapshot.myPendingAbsences > 0) {
      chips.add(_chip(
        Icons.hourglass_top_rounded,
        '${snapshot.myPendingAbsences} ventende søknad${snapshot.myPendingAbsences == 1 ? '' : 'er'}',
        DriftProTheme.warning,
        onOpenFravaer,
      ));
    }
    if (access.canAvvik && snapshot.myOpenTickets > 0) {
      chips.add(_chip(
        AppIcons.ticket,
        '${snapshot.myOpenTickets} åpne avvik',
        DriftProTheme.warning,
        onOpenAvvik,
      ));
    }
    if (snapshot.departmentName != null && snapshot.departmentName!.isNotEmpty) {
      chips.add(_chip(
        Icons.apartment_rounded,
        snapshot.departmentName!,
        DriftProTheme.primaryGreen,
        null,
      ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? DriftProTheme.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
          ),
          boxShadow: DriftProTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                  backgroundImage:
                      profile.avatarUrl != null ? NetworkImage(profile.avatarUrl!) : null,
                  child: profile.avatarUrl == null
                      ? Text(
                          profile.initials,
                          style: const TextStyle(
                            color: DriftProTheme.primaryGreen,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.fullName, style: DriftProTheme.headingSm),
                      Text(
                        '${snapshot.roleLabel} · ${snapshot.dataScopeLabel}',
                        style: DriftProTheme.caption,
                      ),
                    ],
                  ),
                ),
                if (onOpenProfile != null)
                  IconButton(
                    tooltip: 'Min profil',
                    onPressed: onOpenProfile,
                    icon: const Icon(Icons.person_outline_rounded),
                  ),
              ],
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: chips),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Alt i orden — ingen ventende saker i ditt område.',
                  style: DriftProTheme.bodySm.copyWith(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color, VoidCallback? onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: color.withValues(alpha: 0.1),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 12,
        color: color,
      ),
      side: BorderSide(color: color.withValues(alpha: 0.25)),
    );
  }
}
