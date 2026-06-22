import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/gm_storo/gm_storo_download.dart';
import '../../../core/services/gm_storo/gm_storo_excel_export.dart';
import '../../../core/services/gm_storo/gm_storo_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/gm_storo_scan.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Superadmin/leder — oversikt over alle GM & STORO innsendinger.
class GmStoroAdminPanel extends StatefulWidget {
  const GmStoroAdminPanel({super.key, required this.isSuperAdmin});

  final bool isSuperAdmin;

  @override
  State<GmStoroAdminPanel> createState() => _GmStoroAdminPanelState();
}

class _GmStoroAdminPanelState extends State<GmStoroAdminPanel> {
  bool _loading = true;
  List<GmStoroBatch> _batches = [];
  GmStoroBatch? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await GmStoroService.instance.fetchSubmittedBatches();
    if (!mounted) return;
    setState(() {
      _batches = list;
      _selected = list.isNotEmpty ? list.first : null;
      _loading = false;
    });
  }

  void _exportAll() {
    if (_batches.isEmpty) return;
    final bytes = GmStoroExcelExport.exportBatches(_batches);
    final name = 'GM_STORO_alle_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';
    downloadGmStoroExcel(bytes, name);
  }

  void _exportSelected() {
    final b = _selected;
    if (b == null || b.scans.isEmpty) return;
    final bytes = GmStoroExcelExport.exportScans(b.scans);
    final name = 'GM_STORO_${b.id.substring(0, 8)}.xlsx';
    downloadGmStoroExcel(bytes, name);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const DriftProLoadingCenter();

    if (_batches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text('Ingen innsendinger ennå', style: DriftProTheme.headingSm),
              const SizedBox(height: 6),
              Text(
                'Når ansatte trykker Send, vises batchen her.',
                textAlign: TextAlign.center,
                style: DriftProTheme.caption,
              ),
            ],
          ),
        ),
      );
    }

    final selected = _selected;
    final scans = selected?.scans ?? const [];

    return Row(
      children: [
        SizedBox(
          width: 300,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_batches.length} innsendinger',
                        style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Eksporter alle til Excel',
                      onPressed: _exportAll,
                      icon: const Icon(Icons.download_rounded),
                    ),
                    IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _batches.length,
                  itemBuilder: (context, i) {
                    final b = _batches[i];
                    final active = selected?.id == b.id;
                    return Material(
                      color: active
                          ? DriftProTheme.primaryGreen.withValues(alpha: 0.1)
                          : Colors.transparent,
                      child: ListTile(
                        selected: active,
                        title: Text(
                          b.scannerName ?? 'Ansatt',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${b.labelCount} etiketter · ${DateFormat('dd.MM.yyyy HH:mm').format(b.submittedAt ?? b.createdAt)}',
                        ),
                        trailing: Text('${b.labelCount}'),
                        onTap: () => setState(() => _selected = b),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (selected != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  color: DriftProTheme.accentBlue.withValues(alpha: 0.06),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selected.scannerName ?? 'Innsending',
                              style: DriftProTheme.headingSm,
                            ),
                            Text(
                              '${scans.length} etiketter · ${selected.status}',
                              style: DriftProTheme.caption,
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: scans.isEmpty ? null : _exportSelected,
                        icon: const Icon(Icons.table_view),
                        label: const Text('Last ned Excel'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: scans.isEmpty
                    ? const Center(child: Text('Velg en innsending'))
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              DriftProTheme.primaryGreen.withValues(alpha: 0.08),
                            ),
                            columns: const [
                              DataColumn(label: Text('SSCC')),
                              DataColumn(label: Text('Package')),
                              DataColumn(label: Text('Shipment')),
                              DataColumn(label: Text('Consignee')),
                              DataColumn(label: Text('Mottaker')),
                              DataColumn(label: Text('Vekt')),
                              DataColumn(label: Text('Tid')),
                              DataColumn(label: Text('Art.EG')),
                              DataColumn(label: Text('Art.NDC')),
                              DataColumn(label: Text('Dest.')),
                            ],
                            rows: [
                              for (final s in scans)
                                DataRow(cells: [
                                  DataCell(Text(s.data.sscc ?? '')),
                                  DataCell(Text(s.data.packageId ?? '')),
                                  DataCell(Text(s.data.shipmentId ?? '')),
                                  DataCell(Text(s.data.consignee ?? '')),
                                  DataCell(Text(s.data.recipientName ?? '')),
                                  DataCell(Text(s.data.weightKg ?? '')),
                                  DataCell(Text(s.data.readyTime ?? '')),
                                  DataCell(Text(s.data.articleEg ?? '')),
                                  DataCell(Text(s.data.articleNdc ?? '')),
                                  DataCell(Text(s.data.destinationLabel)),
                                ]),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
