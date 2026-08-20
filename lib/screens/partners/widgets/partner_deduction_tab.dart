import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/partner_deduction_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_deduction_case.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import 'partner_deduction_case_sheet.dart';
import 'partner_deduction_compose_panel.dart';
import 'partner_deduction_evidence_gallery.dart';
import 'partner_modern_ui.dart';

/// Bot/Trekk per samarbeidspartner i bedriftsdetalj.
class PartnerDeductionTab extends StatefulWidget {
  const PartnerDeductionTab({
    super.key,
    required this.partner,
    required this.onChanged,
  });

  final Partner partner;
  final VoidCallback onChanged;

  @override
  State<PartnerDeductionTab> createState() => _PartnerDeductionTabState();
}

class _PartnerDeductionTabState extends State<PartnerDeductionTab> {
  List<PartnerDeductionCase> _cases = [];
  bool _loading = true;
  bool _showRegister = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final cid = await SupabaseService.getCurrentCompanyId();
    if (cid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final rows = await PartnerDeductionService.listCases(
      companyId: cid,
      partnerId: widget.partner.id,
    );
    if (mounted) {
      setState(() {
        _cases = rows;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const DriftProLoadingCenter();

    if (_showRegister) {
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _showRegister = false),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Tilbake til historikk'),
            ),
          ),
          Expanded(
            child: PartnerDeductionComposePanel(
              partners: [widget.partner],
              initialPartner: widget.partner,
              onCreated: () {
                setState(() => _showRegister = false);
                _load();
                widget.onChanged();
              },
            ),
          ),
        ],
      );
    }

    final money = NumberFormat.currency(locale: 'nb_NO', symbol: 'kr', decimalDigits: 0);
    final open = _cases.where((c) => !c.isInvoiced).toList();
    final openSum = open.fold<double>(0, (s, c) => s + c.amountNok);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: PartnerModernUi.surface(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEA580C).withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEA580C).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.gavel_rounded, color: Color(0xFFEA580C)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bot / Trekk',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        color: PartnerModernUi.textPrimary(context),
                      ),
                    ),
                    Text(
                      '${open.length} åpne · ${money.format(openSum)}',
                      style: TextStyle(color: PartnerModernUi.muted(context), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => setState(() => _showRegister = true),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Registrer nytt trekk'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFEA580C),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 16),
        Text('Historikk', style: DriftProTheme.labelLg),
        const SizedBox(height: 8),
        if (_cases.isEmpty)
          Text('Ingen trekk registrert.', style: TextStyle(color: PartnerModernUi.muted(context)))
        else
          ..._cases.map((c) => _caseCard(c, money)),
      ],
    );
  }

  Widget _caseCard(PartnerDeductionCase c, NumberFormat money) {
    return Material(
      color: PartnerModernUi.surface(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => PartnerDeductionCaseSheet.show(
          context,
          caseRow: c,
          partner: widget.partner,
          onChanged: () {
            _load();
            widget.onChanged();
          },
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: PartnerModernUi.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(c.caseNumber, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  Text(
                    money.format(c.amountNok),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: c.isInvoiced ? Colors.grey : DriftProTheme.error,
                    ),
                  ),
                ],
              ),
              Text(
                c.templateTitle,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: PartnerModernUi.muted(context),
                ),
              ),
              if (c.evidenceCount > 0) ...[
                const SizedBox(height: 8),
                PartnerDeductionEvidenceGallery(caseId: c.id, compact: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
