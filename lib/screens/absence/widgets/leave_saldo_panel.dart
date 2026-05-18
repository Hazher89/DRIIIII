import 'package:flutter/material.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';
import 'vacation_balance_card.dart';

/// Viser ferie-, egenmeldings- og sykt-barn-saldo — aldri evig «laster».
class LeaveSaldoPanel extends StatelessWidget {
  final AbsenceQuota? quota;
  final CompanyLeaveSettings company;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onRequestSetup;

  const LeaveSaldoPanel({
    super.key,
    required this.quota,
    required this.company,
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
                'Admin må dele ut feriedager for ${DateTime.now().year} før du kan søke ferie. '
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VacationBalanceCard(
          quota: quota!,
          company: company,
          plannedNextYearDays: quota!.vacationDaysTotal,
        ),
        const SizedBox(height: 12),
        QuotaMiniRow(
          label: 'Egenmelding',
          used: quota!.egenmeldingDaysUsed,
          total: company.egenmeldingDaysPerYear,
          color: DriftProTheme.absenceSickSelf,
        ),
        const SizedBox(height: 8),
        QuotaMiniRow(
          label: 'Sykt barn',
          used: quota!.syktBarnDaysUsed,
          total: company.syktBarnDaysLimit(),
          color: DriftProTheme.absenceSickChild,
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
                    '«Saldo» = hvor mange dager du har igjen av ferie, egenmelding og sykt barn i ${quota!.year}.',
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
