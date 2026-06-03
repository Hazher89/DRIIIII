import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/partner/partner_summary_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/partner_summary_meta.dart';
import 'partner_modern_ui.dart';
import 'partner_route_pdf_bytes_url_stub.dart'
    if (dart.library.io) 'partner_route_pdf_bytes_url_io.dart'
    if (dart.library.html) 'partner_route_pdf_bytes_url_web.dart' as pdf_bytes_url;

/// Superadmin: last opp flere oppsummerings-PDF-er, kontroller matching, send til riktig bedrift.
class PartnerSummaryDispatchSheet extends StatefulWidget {
  const PartnerSummaryDispatchSheet({
    super.key,
    required this.partners,
    required this.vehiclesByPartner,
    required this.companyId,
  });

  final List<Partner> partners;
  final Map<String, List<PartnerVehicle>> vehiclesByPartner;
  final String companyId;

  static Future<bool?> show(
    BuildContext context, {
    required List<Partner> partners,
    required Map<String, List<PartnerVehicle>> vehiclesByPartner,
    required String companyId,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PartnerModernUi.surface(context),
      builder: (_) => PartnerSummaryDispatchSheet(
        partners: partners,
        vehiclesByPartner: vehiclesByPartner,
        companyId: companyId,
      ),
    );
  }

  @override
  State<PartnerSummaryDispatchSheet> createState() => _PartnerSummaryDispatchSheetState();
}

class _PartnerSummaryDispatchSheetState extends State<PartnerSummaryDispatchSheet> {
  List<SummaryDispatchDraft> _drafts = [];
  bool _sendSms = true;
  bool _sending = false;

  int get _selectedCount => _drafts.where((d) => d.selected).length;

  Future<void> _pickPdfs() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: true,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final files = <({String name, Uint8List bytes})>[];
    for (final f in picked.files) {
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      files.add((name: f.name, bytes: bytes));
    }
    if (files.isEmpty) return;

    setState(() {
      _drafts = PartnerSummaryService.buildDrafts(
        files: files,
        partners: widget.partners,
        vehiclesByPartner: widget.vehiclesByPartner,
      );
    });
  }

  Future<void> _previewPdf(Uint8List bytes) async {
    final url = await pdf_bytes_url.pdfBytesToViewUrl(bytes);
    if (url != null) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Forhåndsvisning støttes best i nettleser.')),
    );
  }

  Future<void> _send() async {
    if (_selectedCount == 0) return;
    final unassigned = _drafts.where((d) => d.selected && d.partnerId == null).toList();
    if (unassigned.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${unassigned.length} valgte PDF-er mangler bedrift.')),
      );
      return;
    }

    final dupPartners = <String>{};
    final seen = <String>{};
    for (final d in _drafts.where((x) => x.selected && x.partnerId != null)) {
      if (!seen.add(d.partnerId!)) dupPartners.add(d.partnerId!);
    }
    if (dupPartners.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Flere PDF-er til samme bedrift?'),
          content: const Text(
            'Du har valgt mer enn én PDF til samme bedrift i én sending. '
            'Hver bedrift skal kun få sin egen oppsummering. Fortsette likevel?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send likevel')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _sending = true);
    final result = await PartnerSummaryService.sendSelected(
      companyId: widget.companyId,
      drafts: _drafts,
      partners: widget.partners,
      sendSms: _sendSms,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    final msg = StringBuffer('Sendt til ${result.sent} bedrift(er).');
    if (result.errors.isNotEmpty) {
      msg.write('\n${result.errors.take(3).join('\n')}');
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.toString())));
    if (result.sent > 0) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.98,
      builder: (context, scrollCtrl) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Send ut oppsummeringer',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                        ),
                        Text(
                          'Kun superadmin · hver bedrift får kun sin egen PDF',
                          style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: _sending ? null : _pickPdfs,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Velg PDF-er'),
                  ),
                  const SizedBox(width: 8),
                  if (_drafts.isNotEmpty) ...[
                    TextButton(
                      onPressed: () => setState(() {
                        for (final d in _drafts) {
                          d.selected = true;
                        }
                      }),
                      child: const Text('Huk på alle'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        for (final d in _drafts) {
                          d.selected = false;
                        }
                      }),
                      child: const Text('Huk av alle'),
                    ),
                  ],
                ],
              ),
            ),
            if (_drafts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Switch(
                      value: _sendSms,
                      onChanged: _sending ? null : (v) => setState(() => _sendSms = v),
                    ),
                    Expanded(
                      child: Text(
                        _sendSms ? 'Send med SMS-varsel til bedrift' : 'Send uten SMS-varsel',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text('$_selectedCount / ${_drafts.length} valgt'),
                  ],
                ),
              ),
            Expanded(
              child: _drafts.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Last opp én eller flere oppsummerings-PDF-er.\n'
                          'Systemet leser uke, bedrift, datoer og beløp automatisk.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: PartnerModernUi.muted(context)),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: _drafts.length,
                      itemBuilder: (_, i) => _draftCard(_drafts[i]),
                    ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _sending || _selectedCount == 0 ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send),
                    label: Text(_sending ? 'Sender…' : 'Send valgte oppsummeringer'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _draftCard(SummaryDispatchDraft draft) {
    final meta = draft.effectiveMeta;
    final partner = widget.partners.where((p) => p.id == draft.partnerId).firstOrNull;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: draft.selected,
                  onChanged: _sending
                      ? null
                      : (v) => setState(() => draft.selected = v ?? false),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        draft.fileName,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      Text(
                        meta.companyNameRaw,
                        style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Forhåndsvis PDF',
                  onPressed: () => _previewPdf(draft.bytes),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chip('Uke ${meta.weekLabel}'),
                _chip('Faktura ${PartnerSummaryMeta.formatDate(meta.invoiceDate)}'),
                _chip('Betaling ${PartnerSummaryMeta.formatDate(meta.paymentDate)}'),
                _chip(
                  'Transport ${PartnerSummaryMeta.formatAmount(meta.transportTotalExVat)} kr eks mva',
                  highlight: true,
                ),
              ],
            ),
            if (meta.hasMultipleVehicles) ...[
              const SizedBox(height: 8),
              Text('Per bil:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: PartnerModernUi.muted(context))),
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
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: draft.partnerId,
              decoration: InputDecoration(
                labelText: 'Bedrift i DriftPro',
                border: const OutlineInputBorder(),
                isDense: true,
                errorText: draft.partnerId == null ? 'Velg bedrift' : null,
              ),
              items: widget.partners
                  .map(
                    (p) => DropdownMenuItem(
                      value: p.id,
                      child: Text(p.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: _sending
                  ? null
                  : (v) => setState(() {
                        draft.partnerId = v;
                        draft.matchReason = 'Manuelt valgt';
                      }),
            ),
            if (draft.matchReason != null) ...[
              const SizedBox(height: 6),
              Text(
                'Matching: ${draft.matchReason} (${draft.matchScore} poeng)',
                style: TextStyle(
                  fontSize: 10,
                  color: draft.needsReview ? Colors.orange.shade800 : Colors.green.shade800,
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey('week_${draft.localId}_${draft.weekLabel}'),
              initialValue: draft.weekLabel,
              decoration: const InputDecoration(
                labelText: 'Uke (kan endres)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _sending ? null : (v) => draft.weekLabel = v.trim(),
            ),
            if (partner != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Sendes kun til: ${partner.name}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: DriftProTheme.primaryGreenDark),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, {bool highlight = false}) {
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
