import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';

class LeaveQuickActions extends StatelessWidget {
  final void Function(AbsenceType type) onTypeSelected;
  final bool egenmeldingBlocked;
  final VoidCallback? onEgenmeldingBlocked;

  const LeaveQuickActions({
    super.key,
    required this.onTypeSelected,
    this.egenmeldingBlocked = false,
    this.onEgenmeldingBlocked,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hurtigvalg', style: DriftProTheme.headingSm),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _ActionChip(
              label: 'Ferie',
              icon: Icons.beach_access_rounded,
              color: DriftProTheme.absenceVacation,
              isDark: isDark,
              onTap: () => onTypeSelected(AbsenceType.ferie),
            ),
            _ActionChip(
              label: 'Egenmelding',
              icon: Icons.sick_outlined,
              color: DriftProTheme.absenceSickSelf,
              isDark: isDark,
              disabled: egenmeldingBlocked,
              onTap: egenmeldingBlocked
                  ? (onEgenmeldingBlocked ?? () {})
                  : () => onTypeSelected(AbsenceType.egenmelding),
            ),
            _ActionChip(
              label: 'Sykt barn',
              icon: Icons.child_care_rounded,
              color: DriftProTheme.absenceSickChild,
              isDark: isDark,
              onTap: () => onTypeSelected(AbsenceType.syktBarn),
            ),
            _ActionChip(
              label: 'Sykmelding',
              icon: Icons.medical_services_outlined,
              color: DriftProTheme.absenceSickNote,
              isDark: isDark,
              onTap: () => onTypeSelected(AbsenceType.sykmelding),
            ),
            _ActionChip(
              label: 'Permisjon',
              icon: Icons.event_busy_outlined,
              color: DriftProTheme.absenceLeave,
              isDark: isDark,
              onTap: () => onTypeSelected(AbsenceType.permisjon),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;
  final bool disabled;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.isDark,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = disabled ? Colors.grey : color;
    return Material(
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: chipColor.withValues(alpha: disabled ? 0.2 : 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                disabled ? Icons.block : icon,
                color: chipColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                disabled ? '$label (oppbrukt)' : label,
                style: DriftProTheme.labelMd.copyWith(
                  color: disabled ? Colors.grey : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
