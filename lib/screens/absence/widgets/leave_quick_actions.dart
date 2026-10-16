import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';

/// Avansert typevalg — stort, tydelig og enkelt å treffe.
Future<AbsenceType?> showLeaveTypePickerSheet(
  BuildContext context, {
  bool egenmeldingBlocked = false,
  VoidCallback? onEgenmeldingBlocked,
  String? ferieHint,
  String? egenmeldingHint,
  String? syktBarnHint,
  String? employeeName,
}) {
  return showModalBottomSheet<AbsenceType>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final h = MediaQuery.sizeOf(ctx).height;
      return Container(
        constraints: BoxConstraints(maxHeight: h * 0.88),
        decoration: BoxDecoration(
          color: isDark ? DriftProTheme.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Text(
                  'Velg type',
                  style: DriftProTheme.headingSm.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  employeeName != null && employeeName.trim().isNotEmpty
                      ? 'Registrering for $employeeName'
                      : 'Hva skal registreres?',
                  style: DriftProTheme.bodySm.copyWith(
                    color: isDark ? Colors.white70 : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: LeaveQuickActions(
                      dense: false,
                      fullWidth: true,
                      egenmeldingBlocked: egenmeldingBlocked,
                      ferieHint: ferieHint,
                      egenmeldingHint: egenmeldingHint,
                      syktBarnHint: syktBarnHint,
                      onEgenmeldingBlocked: () {
                        Navigator.pop(ctx);
                        onEgenmeldingBlocked?.call();
                      },
                      onTypeSelected: (t) => Navigator.pop(ctx, t),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class LeaveQuickActions extends StatelessWidget {
  final void Function(AbsenceType type) onTypeSelected;
  final bool egenmeldingBlocked;
  final VoidCallback? onEgenmeldingBlocked;
  final String? ferieHint;
  final String? egenmeldingHint;
  final String? syktBarnHint;
  final bool fullWidth;
  final bool dense;

  const LeaveQuickActions({
    super.key,
    required this.onTypeSelected,
    this.egenmeldingBlocked = false,
    this.onEgenmeldingBlocked,
    this.ferieHint,
    this.egenmeldingHint,
    this.syktBarnHint,
    this.fullWidth = false,
    this.dense = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = <Widget>[
      _ActionCard(
        label: 'Ferie',
        description: ferieHint ?? 'Planlagt ferie / ferieavspasering',
        icon: Icons.beach_access_rounded,
        color: DriftProTheme.absenceVacation,
        isDark: isDark,
        fullWidth: fullWidth,
        dense: dense,
        onTap: () => onTypeSelected(AbsenceType.ferie),
      ),
      _ActionCard(
        label: 'Egenmelding',
        description: egenmeldingBlocked
            ? 'Kvoten er brukt opp'
            : (egenmeldingHint ?? 'Kortvarig sykdom uten sykmelding'),
        icon: Icons.sick_outlined,
        color: DriftProTheme.absenceSickSelf,
        isDark: isDark,
        fullWidth: fullWidth,
        dense: dense,
        disabled: egenmeldingBlocked,
        onTap: egenmeldingBlocked
            ? (onEgenmeldingBlocked ?? () {})
            : () => onTypeSelected(AbsenceType.egenmelding),
      ),
      _ActionCard(
        label: 'Sykt barn',
        description: syktBarnHint ?? 'Omsorg for sykt barn under 12 år',
        icon: Icons.child_care_rounded,
        color: DriftProTheme.absenceSickChild,
        isDark: isDark,
        fullWidth: fullWidth,
        dense: dense,
        onTap: () => onTypeSelected(AbsenceType.syktBarn),
      ),
      _ActionCard(
        label: 'Sykmelding',
        description: 'Sykdom med sykmelding fra lege',
        icon: Icons.medical_services_outlined,
        color: DriftProTheme.absenceSickNote,
        isDark: isDark,
        fullWidth: fullWidth,
        dense: dense,
        onTap: () => onTypeSelected(AbsenceType.sykmelding),
      ),
      _ActionCard(
        label: 'Permisjon',
        description: 'Permisjon / fri utenom ferie',
        icon: Icons.event_busy_outlined,
        color: DriftProTheme.absenceLeave,
        isDark: isDark,
        fullWidth: fullWidth,
        dense: dense,
        onTap: () => onTypeSelected(AbsenceType.permisjon),
      ),
    ];

    if (fullWidth) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            items[i],
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hurtigvalg', style: DriftProTheme.headingSm),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items,
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;
  final bool disabled;
  final bool fullWidth;
  final bool dense;

  const _ActionCard({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.isDark,
    required this.onTap,
    this.disabled = false,
    this.fullWidth = false,
    this.dense = true,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = disabled ? Colors.grey : color;
    final card = Material(
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: fullWidth ? double.infinity : null,
          padding: EdgeInsets.symmetric(
            horizontal: fullWidth ? 16 : 14,
            vertical: fullWidth ? 16 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: chipColor.withValues(alpha: disabled ? 0.2 : 0.4),
              width: fullWidth ? 1.5 : 1,
            ),
            gradient: fullWidth && !disabled
                ? LinearGradient(
                    colors: [
                      chipColor.withValues(alpha: isDark ? 0.18 : 0.08),
                      Colors.transparent,
                    ],
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Container(
                width: fullWidth ? 48 : 36,
                height: fullWidth ? 48 : 36,
                decoration: BoxDecoration(
                  color: chipColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  disabled ? Icons.block : icon,
                  color: chipColor,
                  size: fullWidth ? 26 : 20,
                ),
              ),
              const SizedBox(width: 12),
              if (fullWidth)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        disabled ? '$label (oppbrukt)' : label,
                        style: DriftProTheme.labelLg.copyWith(
                          color: disabled ? Colors.grey : null,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: DriftProTheme.caption.copyWith(
                          height: 1.3,
                          color: isDark ? Colors.white60 : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      disabled ? '$label (oppbrukt)' : label,
                      style: DriftProTheme.labelMd.copyWith(
                        color: disabled ? Colors.grey : null,
                      ),
                    ),
                    Text(description, style: DriftProTheme.caption),
                  ],
                ),
              if (fullWidth) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: chipColor.withValues(alpha: 0.7),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return card;
  }
}
