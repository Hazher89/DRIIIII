import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/partner_summary_meta.dart';
import '../widgets/partner_summary_overview_card.dart';
import 'owner_portal_common.dart';

class OwnerPortalDocsPage extends StatefulWidget {
  final Partner partner;
  const OwnerPortalDocsPage({super.key, required this.partner});

  @override
  State<OwnerPortalDocsPage> createState() => _OwnerPortalDocsPageState();
}

class _OwnerPortalDocsPageState extends State<OwnerPortalDocsPage> {
  List<PartnerDocument> _docs = [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await PartnerService.fetchOwnerPortalDocuments(widget.partner.id);
    if (mounted) setState(() { _docs = d; _loading = false; });
  }

  Future<void> _openPdf(PartnerDocument doc) async {
    final p = doc.storagePath;
    if (p == null || p.isEmpty) return;
    try {
      final url = await PartnerService.getDocumentPdfSignedUrl(p);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunne ikke åpne: $e')));
    }
  }

  Future<void> _openDocument(PartnerDocument doc) async {
    if (doc.docCategory != 'summary') {
      await _openPdf(doc);
      return;
    }

    final meta = PartnerSummaryMeta.tryParseFromDescription(doc.description);
    if (meta == null) {
      await _openPdf(doc);
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(doc.title),
        content: SingleChildScrollView(
          child: PartnerSummaryOverviewCard(meta: meta),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Lukk')),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openPdf(doc);
            },
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Åpne full PDF'),
          ),
        ],
      ),
    );
  }

  List<PartnerDocument> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _docs;
    return _docs.where((d) {
      return d.title.toLowerCase().contains(q) ||
          PartnerDocument.documentTypeLabel(d.documentType).toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<PartnerDocument>>{};
    for (final d in _filtered) {
      final key = d.docCategory;
      grouped.putIfAbsent(key, () => []).add(d);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dokumenter'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => signOutFromPortal(context)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Søk i dokumenter…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: _filtered.isEmpty
                      ? const Center(child: Text('Ingen dokumenter delt med bil-eier ennå.'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              for (final entry in grouped.entries) ...[
                                OwnerSectionTitle(title: _categoryLabel(entry.key)),
                                ...entry.value.map((doc) => _docTile(doc)),
                              ],
                            ],
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _docTile(PartnerDocument doc) {
    final meta = doc.docCategory == 'summary'
        ? PartnerSummaryMeta.tryParseFromDescription(doc.description)
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDocument(doc),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    doc.isExpired ? Icons.warning_amber : Icons.description_outlined,
                    color: doc.isExpired ? Colors.orange : DriftProTheme.primaryGreen,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(doc.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              if (meta != null) ...[
                const SizedBox(height: 10),
                PartnerSummaryOverviewCard(meta: meta, compact: true),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 34),
                  child: Text(
                    PartnerDocument.documentTypeLabel(doc.documentType),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _categoryLabel(String cat) {
    switch (cat) {
      case 'agreement':
        return 'Avtaler';
      case 'summary':
        return 'Oppsummeringer';
      default:
        return 'Generelt';
    }
  }
}
