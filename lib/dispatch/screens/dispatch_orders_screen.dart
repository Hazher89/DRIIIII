import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/services/partner/partner_service.dart';
import '../../core/services/partner/route_pdf_text_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../last_mile/models/lm_order.dart';
import '../../last_mile/services/last_mile_order_service.dart';

/// Ordrekø — erstatter SAP som primær inngang.
class DispatchOrdersScreen extends StatefulWidget {
  const DispatchOrdersScreen({super.key});

  @override
  State<DispatchOrdersScreen> createState() => _DispatchOrdersScreenState();
}

class _DispatchOrdersScreenState extends State<DispatchOrdersScreen> {
  List<LmOrder> _orders = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await LastMileOrderService.fetchPending();
    if (mounted) {
      setState(() {
        _orders = list;
        _loading = false;
      });
    }
  }

  Future<void> _importPdf() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final bytes = picked.files.first.bytes;
    if (bytes == null) return;

    setState(() => _busy = true);
    final text = RoutePdfTextService.extractFullText(bytes);
    final n = await LastMileOrderService.importFromPdfText(text);
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$n ordre importert fra PDF')),
      );
      _load();
    }
  }

  Future<void> _importSapInbox() async {
    final cid = await SupabaseService.getCurrentCompanyId();
    if (cid == null) return;
    setState(() => _busy = true);
    var total = 0;
    final inbox = await PartnerService.fetchSapRouteInboxPending(cid);
    for (final item in inbox) {
      final bytes = await PartnerService.downloadRoutePdfBytes(item.pdfStoragePath);
      if (bytes == null) continue;
      final text = RoutePdfTextService.extractFullText(bytes);
      total += await LastMileOrderService.importFromPdfText(text, source: 'sap_legacy');
    }
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$total ordre fra SAP-innboks')),
      );
      _load();
    }
  }

  Future<void> _geocodeAll() async {
    setState(() => _busy = true);
    final n = await LastMileOrderService.geocodePending();
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$n ordre geokodet')));
      _load();
    }
  }

  Future<void> _addManual() async {
    final name = TextEditingController();
    final address = TextEditingController();
    final postal = TextEditingController();
    final city = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ny ordre'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Kunde')),
              TextField(controller: address, decoration: const InputDecoration(labelText: 'Adresse')),
              TextField(controller: postal, decoration: const InputDecoration(labelText: 'Postnr')),
              TextField(controller: city, decoration: const InputDecoration(labelText: 'Sted')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lagre')),
        ],
      ),
    );

    if (ok != true || name.text.trim().isEmpty) return;

    await LastMileOrderService.create(
      LmOrder(
        id: '',
        companyId: '',
        source: 'manual',
        customerName: name.text.trim(),
        addressLine: address.text.trim(),
        postalCode: postal.text.trim().isEmpty ? null : postal.text.trim(),
        city: city.text.trim().isEmpty ? null : city.text.trim(),
        createdAt: DateTime.now(),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _addManual,
                icon: const Icon(Icons.add),
                label: const Text('Ny ordre'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _importPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF → ordre'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _importSapInbox,
                icon: const Icon(Icons.mail_outline),
                label: const Text('SAP-innboks → ordre'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _geocodeAll,
                icon: const Icon(Icons.place_outlined),
                label: const Text('Geokod alle'),
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _orders.isEmpty
                  ? Center(
                      child: Text(
                        'Ingen ordre i kø. Importer PDF eller opprett manuelt.',
                        style: DriftProTheme.bodyMd,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _orders.length,
                        itemBuilder: (ctx, i) {
                          final o = _orders[i];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: ListTile(
                              leading: Icon(
                                o.hasCoordinates ? Icons.place : Icons.place_outlined,
                                color: o.hasCoordinates ? Colors.green : Colors.orange,
                              ),
                              title: Text(o.customerName),
                              subtitle: Text(
                                '${o.addressLine}\n${o.postalCode ?? ''} ${o.city ?? ''} · ${o.source}',
                              ),
                              isThreeLine: true,
                              trailing: Text('${o.weightKg?.toInt() ?? 35} kg'),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
