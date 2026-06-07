import 'package:flutter/material.dart';

import '../../../core/services/partner/partner_summary_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_summary_meta.dart';
import 'partner_route_pdf_actions.dart';
import 'partner_route_pdf_thumbnail.dart';

/// Oppsummerings-PDF i kø — samme kortlayout som AUTO MASS / SAP.
class PartnerSummaryQueueCard extends StatelessWidget {
  final SummaryDispatchDraft draft;
  final Partner? partner;
  final Color accent;
  final Color accentDark;
  final bool checked;
  final bool needsReview;
  final bool busy;
  final VoidCallback onOpenDetails;
  final ValueChanged<bool?> onChecked;
  final VoidCallback? onRemove;

  const PartnerSummaryQueueCard({
    super.key,
    required this.draft,
    required this.partner,
    required this.accent,
    required this.accentDark,
    required this.checked,
    required this.needsReview,
    required this.busy,
    required this.onOpenDetails,
    required this.onChecked,
    this.onRemove,
  });

  PartnerSummaryMeta get _meta => draft.effectiveMeta;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final partnerLabel = partner?.name ?? 'Velg bedrift';
    final amount = PartnerSummaryMeta.formatAmount(_meta.transportTotalExVat);

    return Material(
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenDetails,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: needsReview
                  ? Colors.orange.shade600
                  : checked
                      ? accent.withValues(alpha: 0.55)
                      : isDark
                          ? DriftProTheme.dividerDark
                          : Colors.grey.shade200,
              width: needsReview || checked ? 2 : 1,
            ),
            boxShadow: DriftProTheme.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PartnerRoutePdfThumbnail(
                      bytes: draft.bytes,
                      driverLabel: 'Uke ${_meta.weekLabel}',
                      showFullPage: true,
                      onTapOpen: () => PartnerRoutePdfActions.openPdfBytes(
                        context,
                        bytes: draft.bytes,
                        title: draft.fileName,
                      ),
                    ),
                    Positioned(
                      top: 6,
                      left: 2,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(8),
                        child: Checkbox(
                          value: checked,
                          activeColor: accentDark,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          onChanged: busy ? null : onChecked,
                        ),
                      ),
                    ),
                    if (onRemove != null)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Material(
                          color: Colors.white.withValues(alpha: 0.92),
                          shape: const CircleBorder(),
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            iconSize: 18,
                            tooltip: 'Fjern fra kø',
                            onPressed: busy ? null : onRemove,
                            icon: Icon(Icons.close, color: Colors.grey.shade700),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partnerLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: needsReview ? Colors.orange.shade900 : accentDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Uke ${_meta.weekLabel} · $amount kr eks mva',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                    if (needsReview) ...[
                      const SizedBox(height: 4),
                      Text(
                        draft.matchReason ?? 'Trenger manuell sjekk',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: Colors.orange.shade800),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget buildDetailsForm({
    required BuildContext context,
    required SummaryDispatchDraft draft,
    required List<Partner> partners,
    required Color accentDark,
    required bool needsReview,
    required ValueChanged<String?> onPartnerChanged,
    required ValueChanged<String> onWeekChanged,
    required VoidCallback onPreview,
  }) {
    final meta = draft.effectiveMeta;
    final partner = partners.where((p) => p.id == draft.partnerId).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          draft.fileName,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        const SizedBox(height: 4),
        Text(
          meta.companyNameRaw,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _detailChip('Uke ${meta.weekLabel}'),
            _detailChip('Faktura ${PartnerSummaryMeta.formatDate(meta.invoiceDate)}'),
            _detailChip('Betaling ${PartnerSummaryMeta.formatDate(meta.paymentDate)}'),
            _detailChip(
              'Transport ${PartnerSummaryMeta.formatAmount(meta.transportTotalExVat)} kr',
              highlight: true,
            ),
          ],
        ),
        if (meta.hasMultipleVehicles) ...[
          const SizedBox(height: 10),
          Text('Per bil:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          ...meta.vehicles.map(
            (v) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${v.compactLabel} (${v.unitCode}): ${PartnerSummaryMeta.formatAmount(v.transportExVat)} kr',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          value: draft.partnerId,
          decoration: InputDecoration(
            labelText: 'Bedrift i DriftPro',
            border: const OutlineInputBorder(),
            errorText: draft.partnerId == null ? 'Velg bedrift' : null,
          ),
          items: partners
              .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: onPartnerChanged,
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: ValueKey('week_${draft.localId}_${draft.weekLabel}'),
          initialValue: draft.weekLabel,
          decoration: const InputDecoration(
            labelText: 'Uke (kan endres)',
            border: OutlineInputBorder(),
          ),
          onChanged: onWeekChanged,
        ),
        if (draft.matchReason != null) ...[
          const SizedBox(height: 8),
          Text(
            'Matching: ${draft.matchReason} (${draft.matchScore} poeng)',
            style: TextStyle(
              fontSize: 10,
              color: needsReview ? Colors.orange.shade800 : Colors.green.shade800,
            ),
          ),
        ],
        if (partner != null) ...[
          const SizedBox(height: 8),
          Text(
            'Sendes kun til: ${partner.name}',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accentDark),
          ),
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: onPreview,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Åpne PDF'),
        ),
      ],
    );
  }

  static Widget _detailChip(String label, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? DriftProTheme.primaryGreen.withValues(alpha: 0.12)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: highlight ? DriftProTheme.primaryGreenDark : Colors.black87,
        ),
      ),
    );
  }
}
