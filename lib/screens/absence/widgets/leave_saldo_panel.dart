import 'package:flutter/material.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';
import '../../../models/leave_period_usage.dart';
import 'leave_egenmelding_blocked_sheet.dart';
import 'vacation_balance_card.dart';

/// Viser ferie-, egenmeldings- og sykt-barn-saldo — aldri evig «laster».
class LeaveSaldoPanel extends StatelessWidget {
  final AbsenceQuota? quota;
  final LeavePeriodUsage? periodUsage;
  final int childrenUnder12;
  final int selectedYear;
  final CompanyLeaveSettings company;
  final void Function(AbsenceType type)? onChooseAlternative;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onRequestSetup;

  const LeaveSaldoPanel({
    super.key,
    required this.quota,
    this.periodUsage,
    this.childrenUnder12 = 0,
    required this.selectedYear,
    required this.company,
    this.onChooseAlternative,
    this.isLoading = false,
    this.error,
    this.onRetry,
    this.onRequestSetup,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isLoading) {
      return _card(
        isDark,
        child: const Padding(
          padding: EdgeInsets.all(28),
          child: Center(
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Henter din fraværssaldo…'),
              ],
            ),
          ),
        ),
      );
    }

    if (error != null) {
      return _card(
        isDark,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, color: DriftProTheme.error),
                  const SizedBox(width: 10),
                  Text('Kunne ikke hente saldo', style: DriftProTheme.labelLg),
                ],
              ),
              const SizedBox(height: 8),
              Text(error!, style: DriftProTheme.bodySm),
              const SizedBox(height: 12),
              if (onRetry != null)
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Prøv igjen'),
                ),
            ],
          ),
        ),
      );
    }

    if (quota == null) {
      return _card(
        isDark,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ingen feriedager tildelt ennå', style: DriftProTheme.headingSm),
              const SizedBox(height: 8),
              Text(
                'Admin må dele ut feriedager for $selectedYear før du kan søke ferie det året. '
                'Egenmelding og sykt barn kan likevel registreres når saldo er opprettet.',
                style: DriftProTheme.bodySm,
              ),
              const SizedBox(height: 14),
              if (onRequestSetup != null)
                FilledButton.icon(
                  onPressed: onRequestSetup,
                  icon: const Icon(Icons.add_chart_outlined),
                  label: const Text('Opprett min saldo (standard 25 dager)'),
                ),
            ],
          ),
        ),
      );
    }

    final syktBarnMax = company.syktBarnDaysLimit(childrenUnder12: childrenUnder12);
    final egenExhausted = periodUsage != null &&
        periodUsage!.isEgenmeldingExhausted(company.effectiveEgenmeldingDaysPerYear);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (egenExhausted) ...[
          _card(
            isDark,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: DriftProTheme.warning),
                      const SizedBox(width: 10),
                      Text('Egenmelding brukt opp',
                          style: DriftProTheme.labelLg),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Du kan ikke søke ny egenmelding i ${periodUsage!.window.formatRange()}. '
                    'Bruk sykmelding eller kontakt leder for manuell registrering.',
                    style: DriftProTheme.bodySm,
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => showLeaveEgenmeldingBlockedSheet(
                      context,
                      periodUsage: periodUsage!,
                      maxDays: company.effectiveEgenmeldingDaysPerYear,
                      onChooseAlternative: onChooseAlternative,
                    ),
                    child: const Text('Se alternativer og Lovdata-info'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        VacationBalanceCard(
          quota: quota!,
          company: company,
          plannedNextYearDays: quota!.vacationDaysTotal,
        ),
        const SizedBox(height: 12),
        if (periodUsage != null) ...[
          _card(
            isDark,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.date_range_outlined,
                      size: 18, color: DriftProTheme.primaryGreen),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Egenmelding/sykt barn: periode ${periodUsage!.window.formatRange()} '
                      '(12 mnd fra ansettelsesdato, nullstilles ikke 1. januar).',
                      style: DriftProTheme.caption,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        QuotaMiniRow(
          label: 'Egenmelding',
          used: periodUsage?.egenmeldingDaysUsed ?? quota!.egenmeldingDaysUsed,
          total: company.effectiveEgenmeldingDaysPerYear,
          color: DriftProTheme.absenceSickSelf,
          subtitle: periodUsage != null
              ? '${periodUsage!.egenmeldingPeriodsUsed}/${LeaveRules.egenmeldingMaxPeriodsPerYear} tilfeller'
              : null,
        ),
        const SizedBox(height: 8),
        QuotaMiniRow(
          label: 'Sykt barn',
          used: periodUsage?.syktBarnDaysUsed ?? quota!.syktBarnDaysUsed,
          total: syktBarnMax,
          color: DriftProTheme.absenceSickChild,
          subtitle: childrenUnder12 >= 2
              ? '$childrenUnder12 barn under 12 → ${LeaveRules.syktBarnDaysTwoOrMoreChildren} dager'
              : childrenUnder12 == 1
                  ? '1 barn under 12 → ${LeaveRules.syktBarnDaysPerChildUnder12} dager'
                  : 'Registrer barn i Min profil for riktig kvote',
        ),
        const SizedBox(height: 8),
        _card(
          isDark,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: DriftProTheme.primaryGreen),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ferie telles per kalenderår ($selectedYear). '
                    'Egenmelding og sykt barn telles løpende i 12-månedersperioden over.',
                    style: DriftProTheme.caption,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(bool isDark, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
        ),
      ),
      child: child,
    );
  }
}
