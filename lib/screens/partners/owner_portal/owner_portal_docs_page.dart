import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
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

  Future<void> _open(PartnerDocument doc) async {
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
                                ...entry.value.map(
                                  (doc) => Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: Icon(
                                        doc.isExpired ? Icons.warning_amber : Icons.description_outlined,
                                        color: doc.isExpired ? Colors.orange : DriftProTheme.primaryGreen,
                                      ),
                                      title: Text(doc.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      subtitle: Text(
                                        '${PartnerDocument.documentTypeLabel(doc.documentType)}'
                                        '${doc.expiresAt != null ? ' · Utløp ${ownerFmtDate(doc.expiresAt!)}' : ''}',
                                      ),
                                      trailing: const Icon(Icons.open_in_new),
                                      onTap: () => _open(doc),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
              ],
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
