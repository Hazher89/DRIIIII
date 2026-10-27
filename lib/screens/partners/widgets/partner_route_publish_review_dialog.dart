import 'package:flutter/material.dart';

import '../../../core/constants/route_dispatch_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner_links.dart';
import 'partner_route_pdf_actions.dart';

/// Én rute som skal publiseres — brukes i kontroll-dialogen.
class PartnerRoutePublishReviewEntry {
  final PartnerRouteShare share;
  final String mavi;
  final String partnerName;
  final String? shiftName;
  final String dateLabel;
  final String startLabel;
  /// MAVI-sjåfør / bil-portal har telefon.
  final bool hasDriverPhone;
  /// Bedriftsansvarlig / bileier har telefon.
  final bool hasOwnerPhone;

  const PartnerRoutePublishReviewEntry({
    required this.share,
    required this.mavi,
    required this.partnerName,
    this.shiftName,
    required this.dateLabel,
    required this.startLabel,
    required this.hasDriverPhone,
    this.hasOwnerPhone = false,
  });

  /// Bakoverkompatibilitet for kallesteder som fortsatt bruker [hasPhone].
  bool get hasPhone => hasDriverPhone;

  bool get hasAnyPhone => hasDriverPhone || hasOwnerPhone;
  bool get bothMissingPhone => !hasDriverPhone && !hasOwnerPhone;

  String get fileLabel {
    final title = share.title ?? share.pdfStoragePath.split('/').last;
    final parts = title.split('—');
    return parts.length > 1 ? parts.last.trim() : title;
  }
}

/// Full kontroll-liste med sjåfører og PDF før publisering.
Future<bool> showPartnerRoutePublishReviewDialog({
  required BuildContext context,
  required List<PartnerRoutePublishReviewEntry> entries,
  required int driverCount,
  required bool notifyDriver,
  required String confirmLabel,
  String? dateSyncSummary,
  String? multiLoadNote,
  String? extraSummary,
}) async {
  if (entries.isEmpty) return false;

  final grouped = <String, List<PartnerRoutePublishReviewEntry>>{};
  for (final e in entries) {
    final key = '${e.mavi}|${e.partnerName}';
    grouped.putIfAbsent(key, () => []).add(e);
  }

  // Unike MAVI-sjåfører (grupper) uten egen telefon.
  final driverMissingPhone = grouped.entries
      .where((g) => g.value.every((e) => !e.hasDriverPhone))
      .length;
  // Kun når både sjåfør og bileier mangler — da er det reell SMS-risiko.
  final bothMissing = grouped.entries
      .where((g) => g.value.every((e) => e.bothMissingPhone))
      .length;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 720,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      notifyDriver
                          ? DriftProTheme.primaryGreen
                          : RouteDispatchStatus.cellColor(RouteDispatchStatus.registered),
                      notifyDriver ? const Color(0xFF2E7D32) : const Color(0xFF546E7A),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.fact_check_outlined, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notifyDriver
                                ? 'Kontroller før publisering'
                                : 'Kontroller før registrering',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${entries.length} rute(r) · $driverCount MAVI — åpne PDF og sjekk at MAVI og skift stemmer',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              if (dateSyncSummary != null && dateSyncSummary.trim().isNotEmpty)
                _infoBanner(dateSyncSummary, Colors.blue.shade50, Colors.blue.shade900),
              if (extraSummary != null && extraSummary.trim().isNotEmpty)
                _infoBanner(extraSummary, Colors.grey.shade100, Colors.grey.shade900),
              if (multiLoadNote != null && multiLoadNote.trim().isNotEmpty)
                _infoBanner(multiLoadNote.trim(), Colors.orange.shade50, Colors.orange.shade900),
              if (notifyDriver && driverMissingPhone > 0)
                _infoBanner(
                  bothMissing > 0
                      ? '$driverMissingPhone av $driverCount MAVI-sjåfører mangler egen telefon. '
                          'Bedriftsansvarlig får fortsatt beskjed der telefon finnes. '
                          '$bothMissing MAVI mangler telefon både hos sjåfør og bileier — ingen SMS dit.'
                      : '$driverMissingPhone av $driverCount MAVI-sjåfører mangler egen telefon. '
                          'Bedriftsansvarlig / bileier får fortsatt SMS/app-varsel for disse rutene.',
                  bothMissing > 0 ? Colors.amber.shade50 : const Color(0xFFF0FDF4),
                  bothMissing > 0 ? Colors.amber.shade900 : const Color(0xFF166534),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  children: [
                    for (final group in grouped.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6, top: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${group.value.first.partnerName} · ${group.value.first.mavi}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            _phoneStatusChip(group.value.first),
                            const SizedBox(width: 6),
                            Text(
                              '${group.value.length} PDF',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...group.value.map((e) => _routeTile(ctx, e)),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        notifyDriver
                            ? 'Publiserer ${entries.length} rute(r) med varsel når du bekrefter.'
                            : 'Registrerer ${entries.length} rute(r) uten varsel.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade800,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Avbryt'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: notifyDriver
                            ? DriftProTheme.primaryGreen
                            : RouteDispatchStatus.cellColor(
                                RouteDispatchStatus.registered,
                              ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      icon: Icon(
                        notifyDriver
                            ? Icons.rocket_launch_outlined
                            : Icons.inventory_2_outlined,
                      ),
                      label: Text(confirmLabel),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  return result == true;
}

Widget _phoneStatusChip(PartnerRoutePublishReviewEntry e) {
  final String label;
  final Color bg;
  final Color fg;
  if (e.hasDriverPhone) {
    label = 'Sjåfør SMS';
    bg = const Color(0xFFDCFCE7);
    fg = const Color(0xFF166534);
  } else if (e.hasOwnerPhone) {
    label = 'Bileier får SMS';
    bg = const Color(0xFFE0F2FE);
    fg = const Color(0xFF075985);
  } else {
    label = 'Ingen telefon';
    bg = const Color(0xFFFEE2E2);
    fg = const Color(0xFF991B1B);
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
    ),
  );
}

Widget _infoBanner(String text, Color bg, Color fg) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    color: bg,
    child: Text(
      text,
      style: TextStyle(fontSize: 12, height: 1.4, color: fg, fontWeight: FontWeight.w600),
    ),
  );
}

Widget _routeTile(BuildContext ctx, PartnerRoutePublishReviewEntry e) {
  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: Colors.grey.shade300),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.fileLabel,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '${e.dateLabel} · start ${e.startLabel}${e.shiftName != null ? ' · ${e.shiftName}' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => PartnerRoutePdfActions.openPdf(ctx, e.share),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: const Text('Vis PDF'),
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ],
      ),
    ),
  );
}
