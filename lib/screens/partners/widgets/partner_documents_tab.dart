import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/partner/partner_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import 'partner_ui.dart';

/// Dokumenter for bil-eier — samme funksjoner som HMS-dokumenter, kun eier-tilgang.
class PartnerDocumentsTab extends StatefulWidget {
  final Partner partner;
  final Future<void> Function() onChanged;

  const PartnerDocumentsTab({
    super.key,
    required this.partner,
    required this.onChanged,
  });

  @override
  State<PartnerDocumentsTab> createState() => _PartnerDocumentsTabState();
}

class _PartnerDocumentsTabState extends State<PartnerDocumentsTab> {
  List<PartnerDocument> _docs = [];
  List<Map<String, dynamic>> _folders = [];
  bool _loading = true;
  String _filterType = 'alle';
  String? _selectedFolderId;

  static const _types = ['alle', 'avtale', 'sertifikat', 'transport', 'revisjon', 'okonomi', 'annet'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      PartnerService.fetchDocuments(
        widget.partner.id,
        docCategories: const ['general', 'agreement'],
      ),
      PartnerService.fetchDocumentFolders(partnerId: widget.partner.id),
    ]);
    final d = results[0] as List<PartnerDocument>;
    final folders = results[1] as List<Map<String, dynamic>>;
    if (mounted) {
      setState(() {
        _docs = d.where((x) => x.ownerVisible && !x.driverVisible).toList();
        _folders = folders;
        if (_selectedFolderId == null && folders.isNotEmpty) {
          _selectedFolderId = folders.first['id'] as String?;
        }
        _loading = false;
      });
    }
  }

  List<PartnerDocument> get _filtered {
    final byFolder = _selectedFolderId == null
        ? _docs
        : _docs.where((d) => d.folderId == _selectedFolderId).toList();
    if (_filterType == 'alle') return byFolder;
    return byFolder.where((d) => d.documentType == _filterType).toList();
  }

  Future<void> _upload() async {
    if (_selectedFolderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opprett eller velg mappe først.')),
      );
      return;
    }
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx'],
    );
    if (picked == null || picked.files.isEmpty) return;

    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var docType = 'avtale';
    DateTime? expires;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Last opp dokument til bil-eier'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Dokumentet deles kun med bil-eier portal — ikke MAVI-sjåfører.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Tittel *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: docType,
                  decoration: const InputDecoration(labelText: 'Dokumenttype', border: OutlineInputBorder()),
                  items: _types.where((t) => t != 'alle').map((t) {
                    return DropdownMenuItem(
                      value: t,
                      child: Text(PartnerDocument.documentTypeLabel(t)),
                    );
                  }).toList(),
                  onChanged: (v) => setSt(() => docType = v ?? 'annet'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Beskrivelse', border: OutlineInputBorder()),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Utløpsdato (valgfritt)'),
                  subtitle: Text(
                    expires != null ? DateFormat('dd.MM.yyyy').format(expires!) : 'Aldri / ikke satt',
                  ),
                  trailing: const Icon(Icons.event_outlined),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: expires ?? DateTime.now().add(const Duration(days: 365)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2040),
                    );
                    if (d != null) setSt(() => expires = d);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(onPressed: () => Navigator.pop(ctx, titleCtrl.text.trim().isNotEmpty), child: const Text('Last opp')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final file = picked.files.first;
    final bytes = file.bytes ??
        (file.path != null && !kIsWeb ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) return;

    final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath =
        'company_${widget.partner.companyId}/partner_docs/${widget.partner.id}/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    try {
      final storedPath = await PartnerService.uploadPartnerDocumentFile(
        storagePath: storagePath,
        bytes: bytes,
        mimeType: file.extension != null ? _mimeForExt(file.extension!) : null,
      );
      await PartnerService.addDocumentToFolder(
        PartnerDocument(
          id: '',
          partnerId: widget.partner.id,
          companyId: widget.partner.companyId,
          title: titleCtrl.text.trim(),
          description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
          storagePath: storedPath,
          fileName: file.name,
          mimeType: file.extension,
          documentType: docType,
          expiresAt: expires,
          folderId: _selectedFolderId,
          ownerVisible: true,
          driverVisible: false,
          docCategory: 'general',
          createdAt: DateTime.now(),
        ),
        folderId: _selectedFolderId!,
      );
      await _load();
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dokument delt med bil-eier')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opplasting feilet: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      titleCtrl.dispose();
      descCtrl.dispose();
    }
  }

  Future<void> _createFolder() async {
    final nameCtrl = TextEditingController();
    var shared = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Ny mappe'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Mappenavn',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Skal mappen være felles eller privat?',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 6),
              RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                title: const Text('Privat (kun denne bedriften)'),
                value: false,
                groupValue: shared,
                onChanged: (v) => setSt(() => shared = v ?? false),
              ),
              RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                title: const Text('Felles (synlig for alle bedrifter)'),
                value: true,
                groupValue: shared,
                onChanged: (v) => setSt(() => shared = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim().isNotEmpty),
              child: const Text('Opprett'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) {
      nameCtrl.dispose();
      return;
    }
    final id = await PartnerService.createDocumentFolder(
      companyId: widget.partner.companyId,
      partnerId: widget.partner.id,
      name: nameCtrl.text.trim(),
      shared: shared,
    );
    nameCtrl.dispose();
    await _load();
    if (!mounted) return;
    if (id != null) {
      setState(() => _selectedFolderId = id);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          shared
              ? 'Felles mappe opprettet for alle bedrifter i systemet.'
              : 'Privat mappe opprettet for denne bedriften.',
        ),
      ),
    );
  }

  String? _mimeForExt(String ext) {
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
      default:
        return null;
    }
  }

  Future<void> _open(PartnerDocument d) async {
    final p = d.storagePath;
    if (p == null || p.isEmpty) return;
    try {
      final url = await PartnerService.getDocumentPdfSignedUrl(p);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunne ikke åpne: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final expired = _docs.where((d) => d.isExpired).length;
    final soon = _docs.where((d) {
      if (d.expiresAt == null || d.isExpired) return false;
      return d.expiresAt!.isBefore(DateTime.now().add(const Duration(days: 60)));
    }).length;

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: DriftProTheme.primaryGreen));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          PartnerHeroBanner(
            compact: true,
            title: 'Dokumenter for bil-eier',
            subtitle: 'Avtaler, sertifikater og filer deles kun med bil-eier portal — ikke sjåfører.',
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.folder_shared_outlined, color: Colors.white),
            ),
          ),
          PartnerKpiStrip(
            items: [
              PartnerKpiItem(
                label: 'Dokumenter',
                value: '${_docs.length}',
                color: DriftProTheme.primaryGreen,
                icon: Icons.insert_drive_file_outlined,
              ),
              PartnerKpiItem(
                label: 'Utløper snart',
                value: '$soon',
                color: DriftProTheme.warning,
                icon: Icons.schedule_outlined,
              ),
              PartnerKpiItem(
                label: 'Utløpt',
                value: '$expired',
                color: DriftProTheme.error,
                icon: Icons.error_outline,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _types.map((t) {
              final selected = _filterType == t;
              return FilterChip(
                label: Text(t == 'alle' ? 'Alle' : PartnerDocument.documentTypeLabel(t)),
                selected: selected,
                onSelected: (_) => setState(() => _filterType = t),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedFolderId,
                  decoration: const InputDecoration(
                    labelText: 'Mappe',
                    border: OutlineInputBorder(),
                  ),
                  items: _folders
                      .map(
                        (f) => DropdownMenuItem(
                          value: f['id'] as String,
                          child: Text(
                            '${f['name']} ${f['visibility'] == 'shared' ? '(Felles)' : '(Privat)'}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedFolderId = v),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _createFolder,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Ny mappe'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _upload,
              icon: const Icon(Icons.upload_file),
              label: const Text('Last opp dokument'),
              style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
            ),
          ),
          const SizedBox(height: 12),
          if (_filtered.isEmpty)
            PartnerEmptyState(
              icon: Icons.upload_file_outlined,
              title: 'Ingen dokumenter',
              subtitle: 'Last opp PDF eller bilde — bil-eier får tilgang i sin portal.',
              action: OutlinedButton.icon(
                onPressed: _upload,
                icon: const Icon(Icons.add),
                label: const Text('Last opp'),
              ),
            )
          else
            ..._filtered.map((d) => _docCard(d)),
        ],
      ),
    );
  }

  Widget _docCard(PartnerDocument d) {
    Color? accent;
    if (d.isExpired) {
      accent = DriftProTheme.error;
    } else if (d.expiresAt != null &&
        d.expiresAt!.isBefore(DateTime.now().add(const Duration(days: 60)))) {
      accent = DriftProTheme.warning;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: PartnerUi.surface(context),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        border: Border.all(color: (accent ?? Colors.grey).withValues(alpha: 0.22)),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.insert_drive_file_outlined, color: DriftProTheme.primaryGreen),
        ),
        title: Text(d.title, style: DriftProTheme.labelLg),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${PartnerDocument.documentTypeLabel(d.documentType)} · '
              'Utløper: ${d.expiresAt != null ? DateFormat('dd.MM.yyyy').format(d.expiresAt!) : "Aldri"}',
              style: DriftProTheme.bodySm,
            ),
            if (d.description != null && d.description!.isNotEmpty)
              Text(d.description!, style: DriftProTheme.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            PartnerStatusBadge(
              label: 'Kun bil-eier',
              color: DriftProTheme.accentBlue,
              icon: Icons.admin_panel_settings_outlined,
            ),
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'open') {
              await _open(d);
            } else if (v == 'delete') {
              await PartnerService.deleteDocument(d.id);
              await _load();
              await widget.onChanged();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'open', child: Text('Åpne / last ned')),
            PopupMenuItem(value: 'delete', child: Text('Slett')),
          ],
        ),
        onTap: () => _open(d),
      ),
    );
  }
}
