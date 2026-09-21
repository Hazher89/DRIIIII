import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/partner/partner_driver_deviation_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner_driver_deviation.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Profesjonell detaljvisning for sjåføravvik (kommentar, bilder, video).
Future<void> showPartnerDriverDeviationDetail(
  BuildContext context,
  PartnerDriverDeviation item,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => PartnerDriverDeviationDetailSheet(item: item),
  );
}

class PartnerDriverDeviationDetailSheet extends StatefulWidget {
  const PartnerDriverDeviationDetailSheet({super.key, required this.item});

  final PartnerDriverDeviation item;

  @override
  State<PartnerDriverDeviationDetailSheet> createState() =>
      _PartnerDriverDeviationDetailSheetState();
}

class _PartnerDriverDeviationDetailSheetState
    extends State<PartnerDriverDeviationDetailSheet> {
  final Map<String, String> _resolved = {};
  bool _loadingMedia = true;
  String? _mediaError;

  @override
  void initState() {
    super.initState();
    _resolveMedia();
  }

  Future<void> _resolveMedia() async {
    final refs = [...widget.item.imageUrls, ...widget.item.videoUrls];
    if (refs.isEmpty) {
      setState(() => _loadingMedia = false);
      return;
    }
    try {
      for (final ref in refs) {
        _resolved[ref] =
            await PartnerDriverDeviationService.resolveMediaUrl(ref);
      }
      if (mounted) setState(() => _loadingMedia = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingMedia = false;
          _mediaError = e.toString();
        });
      }
    }
  }

  Future<void> _openUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final customer = item.customerRef?.trim().isNotEmpty == true
        ? item.customerRef!.trim()
        : (item.freightUnit?.trim() ?? '');
    final order = item.orderRef?.trim() ?? '';
    final scheme = Theme.of(context).colorScheme;
    final maxH = MediaQuery.sizeOf(context).height * 0.92;

    return SizedBox(
      height: maxH,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.customerName?.trim().isNotEmpty == true
                            ? item.customerName!.trim()
                            : 'Sjåføravvik',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Rute ${DateFormat('d. MMMM yyyy', 'nb').format(item.routeDate)}'
                        ' · meldt ${DateFormat('d.M.yyyy HH:mm', 'nb').format(item.createdAt.toLocal())}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Lukk',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (customer.isNotEmpty)
                      _chip('FU $customer', Icons.badge_outlined),
                    if (order.isNotEmpty)
                      _chip('Bilag $order', Icons.receipt_long_outlined),
                    _chip(
                      item.status == 'open' ? 'Åpen' : item.status,
                      Icons.flag_outlined,
                      color: DriftProTheme.primaryGreen,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Kommentar',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    item.comment,
                    style: const TextStyle(height: 1.4, fontSize: 15),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Dokumentasjon',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                if (_loadingMedia)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: DriftProLoadingCenter(),
                  )
                else if (_mediaError != null)
                  Text(
                    'Vedlegg kunne ikke lastes: $_mediaError',
                    style: TextStyle(color: Colors.red.shade700),
                  )
                else if (item.imageUrls.isEmpty && item.videoUrls.isEmpty)
                  Text(
                    'Ingen bilder eller video er lagt ved dette avviket.',
                    style: TextStyle(color: Colors.grey.shade600),
                  )
                else ...[
                  if (item.imageUrls.isNotEmpty) ...[
                    SizedBox(
                      height: 200,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: item.imageUrls.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (_, i) {
                          final url = _resolved[item.imageUrls[i]];
                          return InkWell(
                            onTap: url == null ? null : () => _openUrl(url),
                            borderRadius: BorderRadius.circular(14),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: url == null
                                  ? Container(
                                      width: 160,
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.broken_image),
                                    )
                                  : Image.network(
                                      url,
                                      width: 220,
                                      height: 200,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                        width: 160,
                                        color: Colors.grey.shade200,
                                        child: const Icon(Icons.broken_image),
                                      ),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (item.videoUrls.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < item.videoUrls.length; i++)
                          FilledButton.tonalIcon(
                            onPressed: () {
                              final url = _resolved[item.videoUrls[i]];
                              if (url != null) _openUrl(url);
                            },
                            icon: const Icon(Icons.play_circle_outline),
                            label: Text(
                              item.videoUrls.length == 1
                                  ? 'Spill av video'
                                  : 'Video ${i + 1}',
                            ),
                          ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, IconData icon, {Color? color}) {
    final c = color ?? Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tomt resultat for CCC-søk — profesjonell melding.
class PartnerDriverDeviationEmptySearch extends StatelessWidget {
  const PartnerDriverDeviationEmptySearch({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Material(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.search_off_outlined, color: Colors.grey.shade600),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ingen avvik funnet',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Vi fant dessverre ingen sjåføravvik knyttet til «$query». '
                      'Dobbeltsjekk bilagsnummeret (starter med 2…) eller Freight Unit (starter med 4…).',
                      style: TextStyle(
                        height: 1.35,
                        color: Colors.grey.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
