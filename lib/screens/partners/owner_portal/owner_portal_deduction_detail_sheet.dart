import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/partner_deduction_templates.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner_deduction_case.dart';
import '../widgets/partner_deduction_evidence_gallery.dart';
import '../widgets/partner_deduction_logiqrma_panel.dart';
import '../widgets/partner_modern_ui.dart';

/// Bil-eier: full skrivebeskyttet visning av ett trekk (mobil bottom sheet).
class OwnerPortalDeductionDetailSheet {
  OwnerPortalDeductionDetailSheet._();

  static Future<void> show(BuildContext context, PartnerDeductionCase caseRow) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.45,
        maxChildSize: 0.96,
        builder: (_, scroll) => _OwnerPortalDeductionDetailBody(
          caseRow: caseRow,
          scrollController: scroll,
        ),
      ),
    );
  }
}

class _OwnerPortalDeductionDetailBody extends StatelessWidget {
  const _OwnerPortalDeductionDetailBody({
    required this.caseRow,
    required this.scrollController,
  });

  final PartnerDeductionCase caseRow;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final c = caseRow;
    final template = partnerDeductionTemplateById(c.templateId);
    final money = NumberFormat.currency(locale: 'nb_NO', symbol: 'kr', decimalDigits: 0);
    final df = DateFormat('dd.MM.yyyy HH:mm');
    final muted = PartnerModernUi.muted(context);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Text(
          c.displayTraceRef,
          style: DriftProTheme.headingMd.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          money.format(c.amountNok),
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: DriftProTheme.error,
          ),
        ),
        const SizedBox(height: 4),
        Text('Registrert ${df.format(c.createdAt)}', style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 20),
        _section(
          context,
          title: 'Hva gjelder trekket',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.templateTitle, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 6),
              Text(c.shortDescription, style: TextStyle(fontSize: 13, height: 1.4, color: muted)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _section(
          context,
          title: 'Begrunnelse',
          child: Text(
            template.detailParagraph,
            style: TextStyle(fontSize: 13, height: 1.5, color: muted),
          ),
        ),
        if (c.comment?.isNotEmpty == true) ...[
          const SizedBox(height: 14),
          _section(
            context,
            title: 'Kommentar fra MAVI',
            child: Text(
              c.comment!,
              style: const TextStyle(fontSize: 13, height: 1.45, fontStyle: FontStyle.italic),
            ),
          ),
        ],
        if (c.logisticsDescription?.isNotEmpty == true) ...[
          const SizedBox(height: 14),
          _section(
            context,
            title: 'Tilleggskommentar',
            child: Text(
              c.logisticsDescription!,
              style: TextStyle(fontSize: 13, height: 1.45, color: muted),
            ),
          ),
        ],
        if (c.hasLogiqrmaRef) ...[
          const SizedBox(height: 14),
          PartnerDeductionLogiqRmaInfo(caseRow: c),
        ],
        const SizedBox(height: 18),
        Text('Bevis (bilder og video)', style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          'Dokumentasjon lagret av MAVI. Trykk for å åpne i full størrelse.',
          style: TextStyle(fontSize: 12, color: muted, height: 1.35),
        ),
        const SizedBox(height: 12),
        PartnerDeductionEvidenceGallery(caseId: c.id),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: PartnerModernUi.surface(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: PartnerModernUi.border(context)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 20, color: muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Dette er kun en oversikt. Ta kontakt med MAVI dersom du har spørsmål om trekket.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: muted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(BuildContext context, {required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PartnerModernUi.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
