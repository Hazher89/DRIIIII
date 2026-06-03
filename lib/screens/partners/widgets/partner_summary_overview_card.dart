import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner_summary_meta.dart';

/// Oversikt før bil-eier åpner oppsummerings-PDF.
class PartnerSummaryOverviewCard extends StatelessWidget {
  const PartnerSummaryOverviewCard({
    super.key,
    required this.meta,
    this.compact = false,
  });

  final PartnerSummaryMeta meta;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            DriftProTheme.primaryGreen.withValues(alpha: 0.12),
            DriftProTheme.accentBlue.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, color: DriftProTheme.primaryGreenDark, size: compact ? 20 : 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Oppsummering uke ${meta.weekLabel}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: compact ? 14 : 16,
                  ),
                ),
              ),
            ],
          ),
          if (meta.companyNameRaw.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              meta.companyNameRaw,
              style: TextStyle(fontSize: compact ? 11 : 12, color: Colors.grey.shade700),
            ),
          ],
          const SizedBox(height: 12),
          _row('Fakturadato', PartnerSummaryMeta.formatDate(meta.invoiceDate)),
          const SizedBox(height: 6),
          _row('Betalingsdato', PartnerSummaryMeta.formatDate(meta.paymentDate)),
          const SizedBox(height: 10),
          if (meta.hasMultipleVehicles) ...[
            Text(
              'Transport eks mva per bil',
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w800,
                color: DriftProTheme.primaryGreenDark,
              ),
            ),
            const SizedBox(height: 6),
            ...meta.vehicles.map(
              (v) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        v.compactLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${PartnerSummaryMeta.formatAmount(v.transportExVat)} kr',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 20),
            _row(
              'Sum alle biler',
              '${PartnerSummaryMeta.formatAmount(meta.transportTotalExVat)} kr eks mva',
              bold: true,
            ),
          ] else
            _row(
              'Transport eks mva',
              '${PartnerSummaryMeta.formatAmount(meta.transportTotalExVat)} kr',
              bold: true,
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
