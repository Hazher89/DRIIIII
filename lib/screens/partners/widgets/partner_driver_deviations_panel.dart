import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/partner_driver_deviation_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner_driver_deviation.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import 'partner_driver_deviation_detail_sheet.dart';

class PartnerDriverDeviationsPanel extends StatefulWidget {
  const PartnerDriverDeviationsPanel({
    super.key,
    required this.companyId,
    this.partnerId,
    this.title = 'Sjåføravvik fra partnere',
    this.subtitle =
        'Rute-/kundeavvik fra partnerfirmaene (bil-eier/sjåfør). '
        'Ikke HMS-avvik for MAVI-ansatte.',
  });

  final String companyId;

  /// Når satt (partnerportal): kun dette firmaet. Tom for MAVI = alle partnere.
  final String? partnerId;
  final String title;
  final String subtitle;

  @override
  State<PartnerDriverDeviationsPanel> createState() =>
      _PartnerDriverDeviationsPanelState();
}

class _PartnerDriverDeviationsPanelState
    extends State<PartnerDriverDeviationsPanel> {
  final _searchCtrl = TextEditingController();
  List<PartnerDriverDeviation> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await PartnerDriverDeviationService.list(
        companyId: widget.companyId,
        partnerId: widget.partnerId,
        query: _searchCtrl.text,
        limit: 100,
      );
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDetail(PartnerDriverDeviation item) {
    return showPartnerDriverDeviationDetail(context, item);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                widget.subtitle,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Bilag 21… / FU 41…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Søk',
                    onPressed: _load,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
                onSubmitted: (_) => _load(),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const DriftProLoadingCenter()
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Kunne ikke laste sjåføravvik: $_error'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 80),
                            Icon(
                              Icons.inbox_outlined,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: Text(
                                _searchCtrl.text.trim().isEmpty
                                    ? 'Ingen sjåføravvik ennå.'
                                    : 'Vi fant dessverre ingen avvik for dette søket.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: _items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, index) =>
                              _deviationCard(_items[index]),
                        ),
                ),
        ),
      ],
    );
  }

  Widget _deviationCard(PartnerDriverDeviation item) {
    final customer = item.customerRef?.trim().isNotEmpty == true
        ? item.customerRef!.trim()
        : (item.freightUnit?.trim() ?? '');
    final order = item.orderRef?.trim() ?? '';
    final mediaCount = item.imageUrls.length + item.videoUrls.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(item),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.orange.withValues(alpha: 0.14),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.customerName ?? 'Ukjent kunde',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          [
                            if (customer.isNotEmpty) 'FU $customer',
                            if (order.isNotEmpty) 'Bilag $order',
                            DateFormat(
                              'd. MMM yyyy',
                              'nb',
                            ).format(item.routeDate),
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          'Sendt av ${item.reporterLabel}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: DriftProTheme.primaryGreen.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      item.status == 'open' ? 'Åpen' : item.status,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.comment,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (mediaCount > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '${item.imageUrls.length} bilde(r)'
                  '${item.videoUrls.isNotEmpty ? ' · ${item.videoUrls.length} video' : ''}'
                  ' · trykk for å åpne',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
