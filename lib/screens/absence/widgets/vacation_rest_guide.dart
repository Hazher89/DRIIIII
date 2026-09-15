import 'package:flutter/material.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';

/// Tydelig oversikt: restferie, regnestykke og hvordan overføring fungerer.
class VacationRestGuide extends StatelessWidget {
  const VacationRestGuide({
    super.key,
    required this.quota,
    required this.company,
    this.onOpenAdminCarryover,
    this.compact = false,
  });

  final AbsenceQuota quota;
  final CompanyLeaveSettings company;
  final VoidCallback? onOpenAdminCarryover;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final remaining = quota.vacationDaysRemaining;
    final maxCarry = company.maxVacationCarryover;
    final canCarry = quota.carryoverEligible(maxCarry);
    final nextYear = quota.year + 1;
    final lost = (remaining - canCarry).clamp(0, remaining);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [
                        DriftProTheme.primaryGreen.withValues(alpha: 0.22),
                        DriftProTheme.cardDark,
                      ]
                    : const [Color(0xFFE8F5E9), Color(0xFFF7FBF7)],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Restferie ${quota.year}',
                        style: DriftProTheme.labelLg.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$remaining',
                            style: DriftProTheme.headingXl.copyWith(
                              fontSize: 48,
                              height: 1,
                              color: DriftProTheme.primaryGreen,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              remaining == 1 ? 'dag igjen' : 'dager igjen',
                              style: DriftProTheme.bodyMd,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.beach_access_rounded,
                  size: 36,
                  color: DriftProTheme.primaryGreen.withValues(alpha: 0.55),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Slik regnes saldoen',
                  style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                _mathRow(
                  isDark,
                  items: [
                    _MathPart('${quota.vacationDaysTotal}', 'Tildelt'),
                    _MathPart('+', null),
                    _MathPart('${quota.vacationDaysCarriedOver}', 'Fra i fjor'),
                    _MathPart('−', null),
                    _MathPart('${quota.vacationDaysUsed}', 'Brukt'),
                    _MathPart('=', null),
                    _MathPart('$remaining', 'Rest', emphasize: true),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: quota.totalVacationDays > 0
                        ? (quota.vacationDaysUsed / quota.totalVacationDays)
                            .clamp(0.0, 1.0)
                        : 0,
                    minHeight: 8,
                    backgroundColor:
                        DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                    valueColor: const AlwaysStoppedAnimation(
                      DriftProTheme.primaryGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Overføre restferie til $nextYear',
                  style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                _step(
                  1,
                  'Ta ut ferie i ${quota.year}',
                  'Rest = det du ikke har brukt innen årets slutt.',
                  isDark,
                ),
                _step(
                  2,
                  'Maks $maxCarry dager kan flyttes',
                  'Bedriften tillater inntil $maxCarry dager overført '
                      '(ferieloven: ofte inntil ${LeaveRules.defaultMaxCarryoverDays}).',
                  isDark,
                ),
                _step(
                  3,
                  'Overføring skjer ved årsskifte',
                  canCarry > 0
                      ? 'Du kan overføre ca. $canCarry dager til $nextYear'
                          '${lost > 0 ? ' — $lost dager går tapt hvis de ikke tas ut' : ''}.'
                      : remaining <= 0
                          ? 'Ingen rest å overføre — alt er brukt eller saldo er 0.'
                          : 'Ingen dager kan overføres med dagens saldo.',
                  isDark,
                  last: true,
                ),
                if (!compact) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : const Color(0xFFFFF8E7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Enkelt sagt',
                          style: DriftProTheme.caption.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Colors.amber.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '• Restferie = det du har igjen å ta i ${quota.year}.\n'
                          '• «Fra i fjor» = dager som ble overført inn i ${quota.year}.\n'
                          '• Ved nyttår flyttes ubrukt ferie (opptil $maxCarry d) inn som '
                          '«Fra i fjor» på $nextYear — resten må tas ut eller går tapt.\n'
                          '• Hovedferie (18 dager) bør tas 1. juni–30. september.',
                          style: DriftProTheme.bodySm.copyWith(
                            height: 1.4,
                            color: isDark
                                ? Colors.white70
                                : Colors.brown.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (onOpenAdminCarryover != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onOpenAdminCarryover,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('Admin: overfør restferie for alle'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mathRow(bool isDark, {required List<_MathPart> items}) {
    return Wrap(
      spacing: 4,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final p in items)
          if (p.label == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                p.value,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: p.emphasize
                    ? DriftProTheme.primaryGreen.withValues(alpha: 0.12)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.grey.shade50),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: p.emphasize
                      ? DriftProTheme.primaryGreen.withValues(alpha: 0.35)
                      : (isDark
                          ? DriftProTheme.dividerDark
                          : Colors.grey.shade200),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    p.value,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: p.emphasize
                          ? DriftProTheme.primaryGreen
                          : null,
                    ),
                  ),
                  Text(
                    p.label!,
                    style: DriftProTheme.caption.copyWith(fontSize: 10),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _step(
    int n,
    String title,
    String body,
    bool isDark, {
    bool last = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: DriftProTheme.primaryGreen.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: DriftProTheme.primaryGreen,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: DriftProTheme.bodySm.copyWith(
                    color: isDark ? Colors.white60 : Colors.grey.shade700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MathPart {
  const _MathPart(this.value, this.label, {this.emphasize = false});
  final String value;
  final String? label;
  final bool emphasize;
}

/// Kort team-stripe: hvor mange har restferie / kan overføre.
class TeamVacationRestSummary extends StatelessWidget {
  const TeamVacationRestSummary({
    super.key,
    required this.quotas,
    required this.company,
    required this.year,
  });

  final List<AbsenceQuota> quotas;
  final CompanyLeaveSettings company;
  final int year;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final yearQuotas = quotas.where((q) => q.year == year).toList();
    if (yearQuotas.isEmpty) return const SizedBox.shrink();

    final withRest = yearQuotas.where((q) => q.vacationDaysRemaining > 0).length;
    final canCarry = yearQuotas
        .where((q) => q.carryoverEligible(company.maxVacationCarryover) > 0)
        .length;
    final totalRest = yearQuotas.fold<int>(
      0,
      (s, q) => s + q.vacationDaysRemaining.clamp(0, 999),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.surfaceDark : const Color(0xFFF4FAF5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DriftProTheme.primaryGreen.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.beach_access_outlined,
              color: DriftProTheme.primaryGreen, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Restferie $year: $totalRest dager totalt · '
              '$withRest ansatte har rest · '
              '$canCarry kan overføre (maks ${company.maxVacationCarryover} d/person)',
              style: DriftProTheme.caption.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
