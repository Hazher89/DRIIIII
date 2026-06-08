import 'package:flutter/material.dart';

import '../../../core/constants/partner_deduction_logiqrma_descriptions.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner_deduction_case.dart';
import 'partner_modern_ui.dart';

/// LogiqRMA-felter ved registrering av trekk.
class PartnerDeductionLogiqRmaPanel extends StatelessWidget {
  const PartnerDeductionLogiqRmaPanel({
    super.key,
    required this.caseNumberCtrl,
    required this.voucherCtrl,
    required this.commentCtrl,
    required this.selectedComment,
    required this.onCommentSelected,
    this.suggestedComment,
    this.readOnly = false,
  });

  final TextEditingController caseNumberCtrl;
  final TextEditingController voucherCtrl;
  final TextEditingController commentCtrl;
  final String? selectedComment;
  final ValueChanged<String?> onCommentSelected;
  final String? suggestedComment;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Valgfritt — kobler trekket til LogiqRMA og vises for bedriften.',
          style: TextStyle(fontSize: 12, height: 1.4, color: PartnerModernUi.muted(context)),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: caseNumberCtrl,
          readOnly: readOnly,
          decoration: InputDecoration(
            labelText: 'LogiqRMA saksnummer',
            hintText: 'F.eks. 2026-1234',
            prefixIcon: const Icon(Icons.numbers_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: voucherCtrl,
          readOnly: readOnly,
          decoration: InputDecoration(
            labelText: 'Bilagsnummer',
            hintText: 'F.eks. 2026-0456',
            prefixIcon: const Icon(Icons.receipt_long_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Kommentar (velg eller skriv)',
          style: DriftProTheme.labelSm.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (suggestedComment != null && !readOnly)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ActionChip(
              avatar: const Icon(Icons.auto_awesome_outlined, size: 16),
              label: Text('Forslag: $suggestedComment', style: const TextStyle(fontSize: 11)),
              onPressed: () {
                onCommentSelected(suggestedComment);
                commentCtrl.text = suggestedComment!;
              },
            ),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final d in kPartnerDeductionLogiqrmaDescriptions)
              FilterChip(
                label: Text(d, style: const TextStyle(fontSize: 11)),
                selected: selectedComment == d,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: readOnly
                    ? null
                    : (_) {
                        onCommentSelected(d);
                        commentCtrl.text = d;
                      },
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: commentCtrl,
          readOnly: readOnly,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Kommentar (fritekst)',
            hintText: 'Vises for bedriften sammen med saksnummer og bilag',
            alignLabelWithHint: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: readOnly ? null : (_) => onCommentSelected(null),
        ),
      ],
    );
  }
}

/// Lesbar visning av LogiqRMA-referanse (arkiv, saksdetalj, portal).
class PartnerDeductionLogiqRmaInfo extends StatelessWidget {
  const PartnerDeductionLogiqRmaInfo({
    super.key,
    required this.caseRow,
    this.compact = false,
  });

  final PartnerDeductionCase caseRow;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!caseRow.hasLogiqrmaRef) return const SizedBox.shrink();

    final muted = PartnerModernUi.muted(context);
    final rows = <Widget>[
      if (caseRow.logiqrmaCaseNumber?.isNotEmpty == true)
        _row(context, 'LogiqRMA saksnummer', caseRow.logiqrmaCaseNumber!, compact: compact),
      if (caseRow.voucherNumber?.isNotEmpty == true)
        _row(context, 'Bilag', caseRow.voucherNumber!, compact: compact),
      if (caseRow.logisticsDescription?.isNotEmpty == true)
        _row(context, 'Kommentar', caseRow.logisticsDescription!, compact: compact),
    ];

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF7C3AED).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('LogiqRMA', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 8),
          ...rows,
          if (rows.isEmpty)
            Text('Ingen LogiqRMA-referanse', style: TextStyle(fontSize: 12, color: muted)),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value, {required bool compact}) {
    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          '$label: $value',
          style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context)),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12, height: 1.35),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
