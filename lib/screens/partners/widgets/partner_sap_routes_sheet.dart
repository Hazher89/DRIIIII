import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/sap_routes_config.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/sap_route_import_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/open_external_url.dart';
import '../../../models/partner/sap_route_inbox.dart';
import 'partner_route_auto_mass_sheet.dart';

/// Mottatte SAP Backup Form PDF-er → import til AUTO MASS (staged).
class PartnerSapRoutesSheet extends StatefulWidget {
  final List<FleetPartnerVehicleRow> fleet;
  final DateTime initialRouteDate;

  const PartnerSapRoutesSheet({
    super.key,
    required this.fleet,
    required this.initialRouteDate,
  });

  static Future<bool?> show(
    BuildContext context, {
    required List<FleetPartnerVehicleRow> fleet,
    DateTime? routeDate,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height * 0.9;
        return SizedBox(
          height: h,
          child: PartnerSapRoutesSheet(
            fleet: fleet,
            initialRouteDate: routeDate ?? DateTime.now(),
          ),
        );
      },
    );
  }

  @override
  State<PartnerSapRoutesSheet> createState() => _PartnerSapRoutesSheetState();
}

class _PartnerSapRoutesSheetState extends State<PartnerSapRoutesSheet> {
  bool _loading = true;
  bool _importing = false;
  List<SapRouteInboxItem> _items = [];
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;
      final list = await PartnerService.fetchSapRouteInboxPending(cid);
      if (!mounted) return;
      setState(() {
        _items = list;
        _selected
          ..clear()
          ..addAll(list.map((e) => e.id));
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _importAndOpenAutoMass() async {
    if (_importing || _selected.isEmpty) return;
    setState(() => _importing = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) throw Exception('Fant ikke bedrift.');
      final routeDay = DateTime(
        widget.initialRouteDate.year,
        widget.initialRouteDate.month,
        widget.initialRouteDate.day,
      );
      final result = await SapRouteImportService.importPendingToStaged(
        companyId: cid,
        routeDate: routeDay,
        fleet: widget.fleet,
        inboxIds: _selected.toList(),
      );
      if (!mounted) return;
      setState(() => _importing = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Importert ${result.imported} rute(r) til AUTO MASS. '
            '${result.skipped} hoppet over.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );

      await _reload();
      if (!mounted) return;
      if (result.imported > 0) {
        Navigator.pop(context, true);
        if (!context.mounted) return;
        await PartnerRouteAutoMassSheet.show(
          context,
          fleet: widget.fleet,
          routeDate: routeDay,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _importing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import feilet: $e')),
        );
      }
    }
  }

  Future<void> _previewPdf(SapRouteInboxItem item) async {
    try {
      final url = await PartnerService.getRoutePdfSignedUrl(item.pdfStoragePath);
      if (!mounted) return;
      await openExternalUrl(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke åpne PDF: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('d.M.y HH:mm', 'nb');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mottatt ruter fra SAP',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
              ),
              const SizedBox(height: 6),
              Text(
                'SAP sender «${SapRoutesConfig.expectedSubject}» med PDF til '
                '${SapRoutesConfig.inboundAddress} (avsender ${SapRoutesConfig.senderDomain}). '
                'Importer til AUTO MASS for fordeling og publisering.',
                style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.35),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _importing || _selected.isEmpty ? null : _importAndOpenAutoMass,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                  ),
                  icon: _importing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    _selected.isEmpty
                        ? 'Velg ruter'
                        : 'Importer ${_selected.length} og åpne AUTO MASS',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Oppdater',
                onPressed: _loading ? null : _reload,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Ingen ventende SAP-ruter.\n\n'
                          'Når SAP sender til ${SapRoutesConfig.inboundAddress}, '
                          'dukker PDF-ene opp her.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final item = _items[i];
                        final checked = _selected.contains(item.id);
                        return Material(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            leading: Checkbox(
                              value: checked,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selected.add(item.id);
                                  } else {
                                    _selected.remove(item.id);
                                  }
                                });
                              },
                            ),
                            title: Text(
                              item.fileName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            subtitle: Text(
                              '${item.senderEmail ?? item.senderName ?? 'SAP'} · ${timeFmt.format(item.receivedAt.toLocal())}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Forhåndsvis PDF',
                                  icon: const Icon(Icons.picture_as_pdf_outlined),
                                  onPressed: () => _previewPdf(item),
                                ),
                                IconButton(
                                  tooltip: 'Fjern fra kø',
                                  icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                                  onPressed: () async {
                                    await PartnerService.dismissSapRouteInbox(item.id);
                                    await _reload();
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
