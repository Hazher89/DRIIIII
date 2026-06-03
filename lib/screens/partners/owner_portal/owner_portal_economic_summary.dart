import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/partner/partner_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/partner_summary_meta.dart';
import '../widgets/partner_summary_overview_card.dart';

class OwnerEconomicSummaryEntry {
  const OwnerEconomicSummaryEntry({required this.doc, required this.meta});

  final PartnerDocument doc;
  final PartnerSummaryMeta meta;

  DateTime get sortDate =>
      meta.paymentDate ?? meta.invoiceDate ?? doc.createdAt.toLocal();

  double get amount => meta.transportTotalExVat;
}

List<OwnerEconomicSummaryEntry> parseEconomicSummaries(List<PartnerDocument> docs) {
  final out = <OwnerEconomicSummaryEntry>[];
  for (final d in docs) {
    if (d.docCategory != 'summary') continue;
    final meta = PartnerSummaryMeta.tryParseFromDescription(d.description);
    if (meta == null) continue;
    out.add(OwnerEconomicSummaryEntry(doc: d, meta: meta));
  }
  out.sort((a, b) => b.sortDate.compareTo(a.sortDate));
  return out;
}

class OwnerPortalEconomicSummaryHero extends StatelessWidget {
  const OwnerPortalEconomicSummaryHero({
    super.key,
    required this.entry,
    required this.onOpenPdf,
  });

  final OwnerEconomicSummaryEntry entry;
  final VoidCallback onOpenPdf;

  @override
  Widget build(BuildContext context) {
    final meta = entry.meta;
    final amount = PartnerSummaryMeta.formatAmount(meta.transportTotalExVat);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            DriftProTheme.primaryGreen,
            DriftProTheme.primaryGreenDark,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: DriftProTheme.primaryGreen.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Siste oppsummering',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(Icons.receipt_long, color: Colors.white.withValues(alpha: 0.9), size: 28),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Uke ${meta.weekLabel}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (meta.companyNameRaw.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                meta.companyNameRaw,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              '$amount kr',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const Text(
              'Transport eks mva (totalt)',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            _heroDateRow(
              Icons.event_outlined,
              'Faktura',
              PartnerSummaryMeta.formatDate(meta.invoiceDate),
            ),
            const SizedBox(height: 6),
            _heroDateRow(
              Icons.payments_outlined,
              'Betaling',
              PartnerSummaryMeta.formatDate(meta.paymentDate),
            ),
            if (meta.hasMultipleVehicles) ...[
              const SizedBox(height: 12),
              Text(
                'Per bil',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              ...meta.vehicles.map(
                (v) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Text(
                        v.compactLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${PartnerSummaryMeta.formatAmount(v.transportExVat)} kr',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onOpenPdf,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: DriftProTheme.primaryGreenDark,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text(
                  'Åpne full PDF',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroDateRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white70),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class OwnerPortalEconomicTotalsSection extends StatelessWidget {
  const OwnerPortalEconomicTotalsSection({super.key, required this.entries});

  final List<OwnerEconomicSummaryEntry> entries;

  Map<int, Map<int, double>> get _byYearMonth {
    final map = <int, Map<int, double>>{};
    for (final e in entries) {
      final d = e.sortDate;
      map.putIfAbsent(d.year, () => {});
      map[d.year]![d.month] = (map[d.year]![d.month] ?? 0) + e.amount;
    }
    return map;
  }

  double _yearTotal(int year) =>
      _byYearMonth[year]?.values.fold<double>(0, (a, b) => a + b) ?? 0;

  @override
  Widget build(BuildContext context) {
    final years = _byYearMonth.keys.toList()..sort((a, b) => b.compareTo(a));
    if (years.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Text(
            'Inntekt per måned og år',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
        ),
        ...years.map((year) {
          final months = _byYearMonth[year]!.keys.toList()..sort((a, b) => b.compareTo(a));
          final yearSum = _yearTotal(year);
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: ExpansionTile(
              initiallyExpanded: year == years.first,
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              title: Text(
                '$year',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
              ),
              subtitle: Text(
                'Totalt ${PartnerSummaryMeta.formatAmount(yearSum)} kr eks mva',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: DriftProTheme.primaryGreenDark,
                ),
              ),
              children: months.map((m) {
                final sum = _byYearMonth[year]![m]!;
                final label = DateFormat.MMMM('nb').format(DateTime(year, m));
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label[0].toUpperCase() + label.substring(1),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${PartnerSummaryMeta.formatAmount(sum)} kr',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          );
        }),
      ],
    );
  }
}

class OwnerPortalEconomicArchiveList extends StatelessWidget {
  const OwnerPortalEconomicArchiveList({
    super.key,
    required this.entries,
    this.skipFirst = true,
    required this.onTap,
  });

  final List<OwnerEconomicSummaryEntry> entries;
  final bool skipFirst;
  final void Function(OwnerEconomicSummaryEntry) onTap;

  @override
  Widget build(BuildContext context) {
    final list = skipFirst && entries.length > 1 ? entries.sublist(1) : entries;
    if (skipFirst && entries.length <= 1) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'Ingen eldre oppsummeringer ennå.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    if (!skipFirst && list.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text(
            'Arkiv — tidligere uker',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
        ),
        ...list.map((e) {
          final meta = e.meta;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onTap(e),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Uke ${meta.weekLabel}',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                          ),
                        ),
                        Text(
                          '${PartnerSummaryMeta.formatAmount(meta.transportTotalExVat)} kr',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: DriftProTheme.primaryGreenDark,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Betaling ${PartnerSummaryMeta.formatDate(meta.paymentDate)} · '
                      'Faktura ${PartnerSummaryMeta.formatDate(meta.invoiceDate)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    PartnerSummaryOverviewCard(meta: meta, compact: true),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

Future<void> openOwnerSummaryPdf(
  BuildContext context,
  PartnerDocument doc,
) async {
  final p = doc.storagePath;
  if (p == null || p.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF mangler for denne oppsummeringen.')),
      );
    }
    return;
  }
  try {
    final url = await PartnerService.getDocumentPdfSignedUrl(p);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke åpne PDF: $e')),
      );
    }
  }
}

Future<void> showOwnerSummaryDetailSheet(
  BuildContext context,
  OwnerEconomicSummaryEntry entry,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (_, scroll) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: ListView(
          controller: scroll,
          children: [
            Text(
              entry.doc.title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 12),
            PartnerSummaryOverviewCard(meta: entry.meta),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                openOwnerSummaryPdf(context, entry.doc);
              },
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Åpne full PDF'),
            ),
          ],
        ),
      ),
    ),
  );
}
