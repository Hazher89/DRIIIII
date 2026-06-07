import 'package:flutter/material.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';
import '../../../models/leave_period_usage.dart';

/// Profesjonell veiledning når egenmelding er brukt opp (Lovdata / HR-rutine).
Future<void> showLeaveEgenmeldingBlockedSheet(
  BuildContext context, {
  required LeavePeriodUsage periodUsage,
  required int maxDays,
  void Function(AbsenceType type)? onChooseAlternative,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final daysUsed = periodUsage.egenmeldingDaysUsed;
      final periodsUsed = periodUsage.egenmeldingPeriodsUsed;

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DriftProTheme.warning.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.block_flipped,
                      color: DriftProTheme.warning,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Egenmelding er brukt opp',
                      style: DriftProTheme.headingSm,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? DriftProTheme.cardDark : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? DriftProTheme.dividerDark
                        : Colors.grey.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Din periode', style: DriftProTheme.labelMd),
                    const SizedBox(height: 4),
                    Text(
                      periodUsage.window.formatRange(),
                      style: DriftProTheme.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _statRow('Dager brukt', '$daysUsed / $maxDays'),
                    _statRow(
                      'Tilfeller brukt',
                      '$periodsUsed / ${LeaveRules.egenmeldingMaxPeriodsPerYear}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Du kan ikke sende ny egenmelding før neste periode starter. '
                'Dette følger arbeidsmiljøloven § 4-3 og bedriftens fraværsregler.',
                style: DriftProTheme.bodySm,
              ),
              const SizedBox(height: 20),
              Text('Hva kan du gjøre nå?', style: DriftProTheme.labelLg),
              const SizedBox(height: 10),
              if (onChooseAlternative != null) ...[
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onChooseAlternative(AbsenceType.sykmelding);
                  },
                  icon: const Icon(Icons.medical_services_outlined),
                  label: const Text('Registrer sykmelding'),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.support_agent_outlined),
                label: const Text('Kontakt nærmeste leder'),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 18,
                      color: DriftProTheme.primaryGreen,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Leder eller HR kan registrere sykmelding eller annet fravær '
                        'manuelt på dine vegne når du har legeerklæring. '
                        'Kilde: Lovdata / folketrygdloven kap. 8.',
                        style: DriftProTheme.caption,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _statRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: DriftProTheme.caption),
        Text(value, style: DriftProTheme.labelMd),
      ],
    ),
  );
}
