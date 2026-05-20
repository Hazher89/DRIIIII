import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../widgets/partner_ui.dart';

class DriverPortalDocsPage extends StatefulWidget {
  final Partner partner;
  const DriverPortalDocsPage({super.key, required this.partner});

  @override
  State<DriverPortalDocsPage> createState() => _DriverPortalDocsPageState();
}

class _DriverPortalDocsPageState extends State<DriverPortalDocsPage> {
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
    final d = await PartnerService.fetchDriverPortalDocuments(widget.partner.id);
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Søk dokumenter…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Text(
                            'Ingen dokumenter delt med sjåfør ennå.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: PartnerUi.mutedText(context)),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, index) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final doc = _filtered[i];
                            return Card(
                              elevation: 0,
                              child: ListTile(
                                leading: const Icon(Icons.description_outlined),
                                title: Text(doc.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(PartnerDocument.documentTypeLabel(doc.documentType)),
                                trailing: const Icon(Icons.open_in_new),
                                onTap: () => _open(doc),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
