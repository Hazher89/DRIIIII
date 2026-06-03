import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  List<Map<String, dynamic>> _folders = [];
  String _query = '';
  bool _loading = true;
  String? _activeFolderId;
  bool _showMaviDocs = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        PartnerService.fetchOwnerPortalDocuments(widget.partner.id),
        PartnerService.fetchOwnerPortalDocumentFolders(partnerId: widget.partner.id),
      ]);
      if (!mounted) return;
      setState(() {
        _docs = results[0] as List<PartnerDocument>;
        _folders = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke laste dokumenter: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Set<String> get _ownerFolderIds =>
      _folders.map((f) => f['id'] as String?).whereType<String>().toSet();

  List<PartnerDocument> get _maviSharedDocs => _docs
      .where((d) => d.folderId == null || !_ownerFolderIds.contains(d.folderId))
      .toList();

  List<PartnerDocument> get _folderDocs {
    if (_activeFolderId == null) return const [];
    return _docs.where((d) => d.folderId == _activeFolderId).toList();
  }

  List<PartnerDocument> _filterList(List<PartnerDocument> list) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((d) {
      return d.title.toLowerCase().contains(q) ||
          PartnerDocument.documentTypeLabel(d.documentType).toLowerCase().contains(q) ||
          (d.folderName?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<void> _openDocument(PartnerDocument doc) async {
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

  static String _titleFromFileName(String name) {
    var base = name.trim();
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    return base.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String? _mimeForExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'txt':
        return 'text/plain';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _createFolder() async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ny mappe'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Mappenavn',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim().isNotEmpty),
            child: const Text('Opprett'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      nameCtrl.dispose();
      return;
    }
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    try {
      await PartnerService.createOwnerDocumentFolder(
        partnerId: widget.partner.id,
        name: name,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mappe «$name» opprettet')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke opprette mappe: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteFolder(Map<String, dynamic> folder) async {
    final id = folder['id'] as String?;
    if (id == null) return;
    final name = (folder['name'] as String?) ?? 'Mappe';
    final count = _docs.where((d) => d.folderId == id).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett mappe?'),
        content: Text(
          'Mappen «$name» og $count fil(er) slettes permanent. Dette kan ikke angres.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await PartnerService.deleteOwnerDocumentFolder(
        partnerId: widget.partner.id,
        folderId: id,
      );
      if (_activeFolderId == id) setState(() => _activeFolderId = null);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mappe slettet')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sletting feilet: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _upload() async {
    if (_activeFolderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Åpne en mappe før du laster opp filer.')),
      );
      return;
    }
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: true,
      type: FileType.any,
    );
    if (picked == null || picked.files.isEmpty) return;

    final files = picked.files;
    final titleCtrls = <TextEditingController>[
      for (final f in files) TextEditingController(text: _titleFromFileName(f.name)),
    ];
    final multi = files.length > 1;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(multi ? 'Last opp ${files.length} filer' : 'Last opp fil'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Kun superadmin og MAVI-ansatte du gir tilgang til kan se filene i denne mappen.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                if (multi)
                  ...List.generate(files.length, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: titleCtrls[i],
                        decoration: InputDecoration(
                          labelText: files[i].name,
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    );
                  })
                else
                  TextField(
                    controller: titleCtrls.first,
                    decoration: const InputDecoration(labelText: 'Tittel *', border: OutlineInputBorder()),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () {
              if (titleCtrls.every((c) => c.text.trim().isNotEmpty)) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text(multi ? 'Last opp alle' : 'Last opp'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) {
      for (final c in titleCtrls) {
        c.dispose();
      }
      return;
    }

    var uploaded = 0;
    String? lastError;
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final bytes = file.bytes ??
          (file.path != null && !kIsWeb ? await File(file.path!).readAsBytes() : null);
      if (bytes == null) {
        lastError = 'Kunne ikke lese ${file.name}';
        continue;
      }
      final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final storagePath =
          'company_${widget.partner.companyId}/partner_docs/${widget.partner.id}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      try {
        final storedPath = await PartnerService.uploadPartnerDocumentFile(
          storagePath: storagePath,
          bytes: bytes,
          mimeType: file.extension != null ? _mimeForExt(file.extension!) : null,
        );
        await PartnerService.addOwnerPortalDocumentToFolder(
          PartnerDocument(
            id: '',
            partnerId: widget.partner.id,
            companyId: widget.partner.companyId,
            title: titleCtrls[i].text.trim(),
            storagePath: storedPath,
            fileName: file.name,
            mimeType: file.extension,
            documentType: 'annet',
            folderId: _activeFolderId,
            ownerVisible: true,
            driverVisible: false,
            docCategory: 'general',
            createdAt: DateTime.now(),
          ),
          folderId: _activeFolderId!,
        );
        uploaded++;
      } catch (e) {
        lastError = '$e';
      }
    }

    for (final c in titleCtrls) {
      c.dispose();
    }
    await _load();
    if (!mounted) return;
    if (uploaded == files.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uploaded == 1 ? 'Fil lastet opp' : '$uploaded filer lastet opp')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$uploaded av ${files.length} lastet opp. ${lastError ?? ""}'),
          backgroundColor: uploaded > 0 ? Colors.orange : Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteDocument(PartnerDocument doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett fil?'),
        content: Text('«${doc.title}» slettes permanent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await PartnerService.deleteDocuments([doc.id]);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sletting feilet: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final inFolder = _activeFolderId != null;
    final showingMavi = _showMaviDocs && !inFolder;
    final listDocs = inFolder
        ? _filterList(_folderDocs)
        : showingMavi
            ? _filterList(_maviSharedDocs)
            : const <PartnerDocument>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          inFolder
              ? (_folders.cast<Map<String, dynamic>?>().firstWhere(
                    (f) => f?['id'] == _activeFolderId,
                    orElse: () => null,
                  )?['name'] as String?) ??
                  'Mappe'
              : showingMavi
                  ? 'Dokumenter fra MAVI'
                  : 'Dokumenter',
        ),
        leading: (inFolder || showingMavi)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _activeFolderId = null;
                  _showMaviDocs = false;
                  _query = '';
                }),
              )
            : null,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => signOutFromPortal(context)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (!inFolder)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Søk…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: inFolder
                        ? _folderBody(listDocs)
                        : showingMavi
                            ? _docsList(listDocs, canDelete: false)
                            : _homeBody(),
                  ),
                ),
              ],
            ),
      floatingActionButton: inFolder
          ? FloatingActionButton.extended(
              onPressed: _upload,
              icon: const Icon(Icons.upload_file),
              label: const Text('Last opp'),
              backgroundColor: DriftProTheme.primaryGreen,
            )
          : null,
    );
  }

  Widget _homeBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Opprett egne mapper og last opp alle filtyper. '
              'Kun du, MAVI superadmin og ansatte du får tilgang til kan se innholdet.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
              child: Text('Mine mapper', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            OutlinedButton.icon(
              onPressed: _createFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Ny mappe'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_folders.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Ingen mapper ennå. Opprett en mappe for å laste opp filer.')),
          )
        else
          ..._folders.map((f) {
            final id = f['id'] as String?;
            final count = _docs.where((d) => d.folderId == id).length;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: const Icon(Icons.folder, color: Color(0xFFF4B400), size: 28),
                title: Text((f['name'] as String?) ?? 'Mappe', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(count == 0 ? 'Tom mappe' : '$count ${count == 1 ? "fil" : "filer"}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'open' && id != null) setState(() => _activeFolderId = id);
                    if (v == 'delete') _deleteFolder(f);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'open', child: Text('Åpne')),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Slett mappe', style: TextStyle(color: DriftProTheme.error)),
                    ),
                  ],
                ),
                onTap: id != null ? () => setState(() => _activeFolderId = id) : null,
              ),
            );
          }),
        const SizedBox(height: 16),
        OwnerSectionTitle(title: 'Fra MAVI'),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.folder_shared_outlined, color: DriftProTheme.primaryGreen, size: 26),
            title: const Text('Dokumenter delt med deg', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(
              _maviSharedDocs.isEmpty
                  ? 'Ingen dokumenter utenfor egne mapper'
                  : '${_maviSharedDocs.length} dokument(er)',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _maviSharedDocs.isEmpty
                ? null
                : () => setState(() => _showMaviDocs = true),
          ),
        ),
      ],
    );
  }

  Widget _folderBody(List<PartnerDocument> docs) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Søk i mappen…',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 12),
        if (docs.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('Ingen filer i mappen. Trykk «Last opp» for å legge til.'),
            ),
          )
        else
          ...docs.map((d) => _docTile(d, canDelete: true)),
      ],
    );
  }

  Widget _docsList(List<PartnerDocument> docs, {required bool canDelete}) {
    if (docs.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Center(child: Text('Ingen dokumenter')),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: docs.map((d) => _docTile(d, canDelete: canDelete)).toList(),
    );
  }

  Widget _docTile(PartnerDocument doc, {required bool canDelete}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDocument(doc),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                doc.isExpired ? Icons.warning_amber : Icons.insert_drive_file_outlined,
                color: doc.isExpired ? Colors.orange : DriftProTheme.primaryGreen,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doc.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (doc.fileName != null)
                      Text(
                        doc.fileName!,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    if (doc.expiresAt != null)
                      Text(
                        'Utløper ${DateFormat('dd.MM.yyyy').format(doc.expiresAt!)}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                  ],
                ),
              ),
              if (canDelete)
                IconButton(
                  tooltip: 'Slett',
                  icon: const Icon(Icons.delete_outline, color: DriftProTheme.error),
                  onPressed: () => _deleteDocument(doc),
                ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
