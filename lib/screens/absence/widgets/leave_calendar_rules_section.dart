import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';
import 'leave_rules_panel.dart';

/// Lovdata-tips under kalender — kontekstuelt for ferie eller fravær.
class LeaveCalendarRulesSection extends StatelessWidget {
  final bool vacationTab;
  final CompanyLeaveSettings companySettings;

  const LeaveCalendarRulesSection({
    super.key,
    required this.vacationTab,
    required this.companySettings,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.gavel_rounded, color: DriftProTheme.primaryGreen, size: 22),
          ),
          title: Text(
            vacationTab ? 'Ferieregler og tips' : 'Fraværsregler og tips',
            style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text('Lovdata · arbeidsmiljøloven · folketrygdloven · ferieloven'),
          children: [
            if (vacationTab) ...[
              _companyChip(
                'Hovedferie skal som hovedregel tas 1. juni – 30. september',
                Icons.wb_sunny_outlined,
                DriftProTheme.absenceVacation,
              ),
              const SizedBox(height: 10),
            ] else ...[
              _quotaSummary(isDark),
              const SizedBox(height: 12),
            ],
            LeaveRulesPanel(
              highlightType: vacationTab ? AbsenceType.ferie : null,
              compact: true,
            ),
            if (vacationTab) ...[
              const SizedBox(height: 8),
              ...LeaveRules.managerOverviewCards()
                  .where((c) =>
                      c.title == LeaveRules.lovdataArbeidsmiljoTitle ||
                      c.title == LeaveRules.lovdataPersonvernTitle ||
                      c.title == LeaveRules.lovdataTipsTitle)
                  .map((c) => _extraRuleTile(c, isDark)),
            ],
            if (!vacationTab) ...[
              const SizedBox(height: 8),
              ...LeaveRules.managerOverviewCards()
                  .where((c) =>
                      c.title != LeaveRules.lovdataFerieTitle &&
                      c.title != LeaveRules.lovdataTipsTitle)
                  .map(
                    (c) => _extraRuleTile(c, isDark),
                  ),
            ],
            const SizedBox(height: 12),
            _lovdataLink(context),
          ],
        ),
      ),
    );
  }

  Widget _quotaSummary(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DriftProTheme.primaryGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bedriftens grenser (HR)', style: DriftProTheme.labelMd),
          const SizedBox(height: 8),
          _quotaRow(
            'Egenmelding',
            '${companySettings.egenmeldingConsecutiveMax} dager om gangen · '
            'maks ${companySettings.effectiveEgenmeldingDaysPerYear} dager/år',
          ),
          _quotaRow(
            'Sykt barn',
            '${LeaveRules.syktBarnDaysPerChildUnder12} dager (1 barn) · '
            '${LeaveRules.syktBarnDaysTwoOrMoreChildren} dager (2+ barn)',
          ),
          _quotaRow(
            'Overføring ferie',
            'Maks ${companySettings.maxVacationCarryover} dager til neste år',
          ),
        ],
      ),
    );
  }

  Widget _quotaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: DriftProTheme.bodySm.copyWith(color: Colors.black87),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _companyChip(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: DriftProTheme.bodySm)),
        ],
      ),
    );
  }

  Widget _extraRuleTile(LeaveRuleCard card, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.surfaceDark : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(card.title, style: DriftProTheme.labelMd),
          const SizedBox(height: 4),
          Text(card.body, style: DriftProTheme.caption.copyWith(height: 1.4)),
        ],
      ),
    );
  }

  Widget _lovdataLink(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => launchUrl(
          Uri.parse('https://lovdata.no'),
          mode: LaunchMode.externalApplication,
        ),
        icon: const Icon(Icons.open_in_new, size: 16),
        label: const Text('Åpne Lovdata.no'),
      ),
    );
  }
}
