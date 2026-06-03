import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/permissions/user_access.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../shared_routines_hub_screen.dart';
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
  String? _activeFolderId;
  bool _selectMode = false;
  final Set<String> _selectedDocIds = {};
  static const String _sharedHubFolderId = '__shared_routines__';

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
        _loading = false;
      });
    }
  }

  List<PartnerDocument> get _filtered {
    final byFolder = _activeFolderId == null
        ? _docs
        : _docs.where((d) => d.folderId == _activeFolderId).toList();
    if (_filterType == 'alle') return byFolder;
    return byFolder.where((d) => d.documentType == _filterType).toList();
  }

  static String _titleFromFileName(String name) {
    var base = name.trim();
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    return base.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<void> _upload() async {
    if (_activeFolderId == null || _activeFolderId == _sharedHubFolderId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gå inn i en mappe først.')),
      );
      return;
    }
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx'],
    );
    if (picked == null || picked.files.isEmpty) return;

    final files = picked.files;
    final titleCtrls = <TextEditingController>[
      for (final f in files) TextEditingController(text: _titleFromFileName(f.name)),
    ];
    final descCtrl = TextEditingController();
    var docType = 'avtale';
    DateTime? expires;
    final multi = files.length > 1;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(multi ? 'Last opp ${files.length} dokumenter' : 'Last opp dokument til bil-eier'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Dokumentet deles kun med bil-eier portal — ikke MAVI-sjåfører.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  if (multi) ...[
                    Text(
                      '${files.length} filer valgt — tittel fra filnavn:',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
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
                    }),
                  ] else
                    TextField(
                      controller: titleCtrls.first,
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
                    decoration: InputDecoration(
                      labelText: multi ? 'Beskrivelse (felles)' : 'Beskrivelse',
                      border: const OutlineInputBorder(),
                    ),
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
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(
              onPressed: () {
                final allTitles = titleCtrls.every((c) => c.text.trim().isNotEmpty);
                Navigator.pop(ctx, allTitles);
              },
              child: Text(multi ? 'Last opp alle' : 'Last opp'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) {
      for (final c in titleCtrls) {
        c.dispose();
      }
      descCtrl.dispose();
      return;
    }

    final description = descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim();
    var uploaded = 0;
    String? lastError;

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final title = titleCtrls[i].text.trim();
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
        await PartnerService.addDocumentToFolder(
          PartnerDocument(
            id: '',
            partnerId: widget.partner.id,
            companyId: widget.partner.companyId,
            title: title,
            description: description,
            storagePath: storedPath,
            fileName: file.name,
            mimeType: file.extension,
            documentType: docType,
            expiresAt: expires,
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
    descCtrl.dispose();

    await _load();
    await widget.onChanged();
    if (!mounted) return;

    if (uploaded == files.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uploaded == 1 ? 'Dokument delt med bil-eier' : '$uploaded dokumenter delt med bil-eier',
          ),
        ),
      );
    } else if (uploaded > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$uploaded av ${files.length} lastet opp. ${lastError ?? ""}'),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opplasting feilet: ${lastError ?? "ukjent"}'),
          backgroundColor: Colors.red,
        ),
      );
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
    final folderName = nameCtrl.text.trim();
    final id = await PartnerService.createDocumentFolder(
      companyId: widget.partner.companyId,
      partnerId: widget.partner.id,
      name: folderName,
      shared: shared,
    );
    nameCtrl.dispose();
    await _load();
    if (!mounted) return;
    if (id != null) {
      setState(() {
        _folders = [
          ..._folders,
          {
            'id': id,
            'name': folderName,
            'visibility': shared ? 'shared' : 'private',
          },
        ]..sort((a, b) => (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));
        _activeFolderId = id;
      });
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

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selectedDocIds.clear();
    });
  }

  Future<bool> _confirmPermanentDelete({
    required String title,
    required String message,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slett permanent'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteDocuments(Iterable<String> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return;
    final ok = await _confirmPermanentDelete(
      title: list.length == 1 ? 'Slett dokument?' : 'Slett ${list.length} dokumenter?',
      message: list.length == 1
          ? 'Filen fjernes permanent fra systemet og bil-eier portal.'
          : 'Alle valgte filer fjernes permanent fra systemet og bil-eier portal.',
    );
    if (!ok || !mounted) return;

    await PartnerService.deleteDocuments(list);
    _exitSelectMode();
    await _load();
    await widget.onChanged();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(list.length == 1 ? 'Dokument slettet' : '${list.length} dokumenter slettet')),
    );
  }

  Future<void> _manageFolderAccess(Map<String, dynamic> folder) async {
    final folderId = folder['id'] as String?;
    if (folderId == null) return;
    final me = await SupabaseService.fetchCurrentUserProfile();
    if (me == null || !me.isSuperAdmin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kun superadmin kan gi tilgang til bedriftens mapper')),
      );
      return;
    }

    var grants = await PartnerService.fetchDocumentFolderAccess(folderId);
    final staff = (await SupabaseService.fetchProfiles(companyId: widget.partner.companyId))
        .where((p) => p.partnerId == null && p.id != me.id)
        .toList();

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          Future<void> reload() async {
            grants = await PartnerService.fetchDocumentFolderAccess(folderId);
            setSt(() {});
          }

          return AlertDialog(
            title: Text('Tilgang: ${folder['name'] ?? 'Mappe'}'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Bedriftens private mappe. Kun superadmin, bedriftsansvarlig og valgte MAVI-ansatte ser innholdet.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    const Text('Har tilgang', style: TextStyle(fontWeight: FontWeight.w700)),
                    if (grants.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Kun superadmin og bedriftsansvarlig (ingen ekstra ansatte)'),
                      )
                    else
                      ...grants.map((g) {
                        final prof = g['profiles'] as Map<String, dynamic>?;
                        final pid = g['profile_id'] as String? ?? prof?['id'] as String?;
                        final label = prof?['full_name'] as String? ?? prof?['email'] as String? ?? pid ?? '';
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(label),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: DriftProTheme.error),
                            onPressed: () async {
                              if (pid == null) return;
                              await PartnerService.revokeDocumentFolderAccess(
                                folderId: folderId,
                                profileId: pid,
                              );
                              await reload();
                            },
                          ),
                        );
                      }),
                    const Divider(height: 24),
                    const Text('Legg til MAVI-ansatt', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    ...staff.map((p) {
                      final has = grants.any((g) => g['profile_id'] == p.id);
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.fullName.isNotEmpty ? p.fullName : (p.email ?? p.id)),
                        subtitle: Text(p.role.name),
                        trailing: has
                            ? const Icon(Icons.check, color: DriftProTheme.primaryGreen)
                            : TextButton(
                                child: const Text('Gi tilgang'),
                                onPressed: () async {
                                  await PartnerService.grantDocumentFolderAccess(
                                    folderId: folderId,
                                    profileId: p.id,
                                  );
                                  await reload();
                                },
                              ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Lukk')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteFolder(Map<String, dynamic> folder) async {
    final id = folder['id'] as String?;
    if (id == null) return;
    if (folder['owner_managed'] == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bedriftens mapper slettes av bedriftsansvarlig i partnerportalen'),
        ),
      );
      return;
    }
    final name = (folder['name'] as String?) ?? 'Mappe';
    final shared = (folder['visibility'] as String?) == 'shared';
    final count = _docs.where((d) => d.folderId == id).length;

    final ok = await _confirmPermanentDelete(
      title: 'Slett mappe?',
      message: shared
          ? 'Mappen «$name» og $count dokument(er) slettes permanent for alle partnere i bedriften. Dette kan ikke angres.'
          : 'Mappen «$name» og $count dokument(er) slettes permanent. Dette kan ikke angres.',
    );
    if (!ok || !mounted) return;

    final removed = await PartnerService.deleteDocumentFolder(
      folderId: id,
      companyId: widget.partner.companyId,
    );
    if (_activeFolderId == id) {
      setState(() => _activeFolderId = null);
    }
    _exitSelectMode();
    await _load();
    await widget.onChanged();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Mappe slettet ($removed dokumenter)')),
    );
  }

  Future<void> _deleteActiveFolder() async {
    final id = _activeFolderId;
    if (id == null || id == _sharedHubFolderId) return;
    final folder = _folders.cast<Map<String, dynamic>?>().firstWhere(
          (f) => f?['id'] == id,
          orElse: () => null,
        );
    if (folder == null) return;
    await _deleteFolder(folder);
  }

  Map<String, dynamic>? _folderById(String? id) {
    if (id == null) return null;
    for (final f in _folders) {
      if (f['id'] == id) return f;
    }
    return null;
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
          const SizedBox(height: 10),
          Row(
            children: [
              if (_activeFolderId != null)
                IconButton(
                  tooltip: 'Tilbake til mapper',
                  onPressed: () {
                    _exitSelectMode();
                    setState(() => _activeFolderId = null);
                  },
                  icon: const Icon(Icons.arrow_back),
                ),
              Expanded(
                child: Text(
                  _activeFolderId == null
                      ? 'Mapper'
                      : (_folderById(_activeFolderId)?['name'] as String?) ?? 'Mappeinnhold',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              if (_activeFolderId == null)
                OutlinedButton.icon(
                  onPressed: _createFolder,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Ny mappe'),
                )
              else if (_activeFolderId != _sharedHubFolderId) ...[
                if (_selectMode) ...[
                  TextButton(
                    onPressed: _selectedDocIds.isEmpty
                        ? null
                        : () => _deleteDocuments(_selectedDocIds),
                    child: Text(
                      'Slett (${_selectedDocIds.length})',
                      style: const TextStyle(color: DriftProTheme.error),
                    ),
                  ),
                  TextButton(onPressed: _exitSelectMode, child: const Text('Ferdig')),
                ] else
                  TextButton.icon(
                    onPressed: _filtered.isEmpty
                        ? null
                        : () => setState(() => _selectMode = true),
                    icon: const Icon(Icons.checklist_outlined, size: 18),
                    label: const Text('Velg'),
                  ),
                IconButton(
                  tooltip: 'Slett mappe og alt innhold',
                  onPressed: _deleteActiveFolder,
                  icon: const Icon(Icons.delete_forever_outlined, color: DriftProTheme.error),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (_activeFolderId == null) ...[
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                SizedBox(
                  width: 150,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SharedRoutinesHubScreen(canManage: true),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(10),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.folder, color: Color(0xFFF4B400), size: 34),
                          SizedBox(height: 4),
                          Text(
                            'Felles dokumenter',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Felles',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF1D4ED8)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ..._folders.map(
                  (f) => _folderTile(
                    folder: f,
                    docCount: _docs.where((d) => d.folderId == f['id']).length,
                    onOpen: () {
                      _exitSelectMode();
                      setState(() => _activeFolderId = f['id'] as String?);
                    },
                    onDelete: () => _deleteFolder(f),
                    onManageAccess: f['owner_managed'] == true
                        ? () => _manageFolderAccess(f)
                        : null,
                  ),
                ),
              ],
            ),
          ] else ...[
            if (_activeFolderId != _sharedHubFolderId) ...[
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
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _upload,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Last opp dokumenter'),
                  style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
                ),
              ),
              const SizedBox(height: 12),
              if (_filtered.isEmpty)
                PartnerEmptyState(
                  icon: Icons.upload_file_outlined,
                  title: 'Ingen dokumenter',
                  subtitle: 'Last opp én eller flere PDF/bilder — bil-eier får tilgang i sin portal.',
                  action: OutlinedButton.icon(
                    onPressed: _upload,
                    icon: const Icon(Icons.add),
                    label: const Text('Last opp'),
                  ),
                )
              else
                ..._filtered.map((d) => _docCard(d)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _folderTile({
    required Map<String, dynamic> folder,
    required int docCount,
    required VoidCallback onOpen,
    required VoidCallback onDelete,
    VoidCallback? onManageAccess,
  }) {
    final title = (folder['name'] as String?) ?? 'Mappe';
    final shared = (folder['visibility'] as String?) == 'shared';
    final ownerManaged = folder['owner_managed'] == true;

    return SizedBox(
      width: 150,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      ownerManaged ? Icons.folder_special_outlined : Icons.folder,
                      color: const Color(0xFFF4B400),
                      size: 34,
                    ),
                    const Spacer(),
                    if (onManageAccess != null)
                      IconButton(
                        tooltip: 'Mappe-tilgang',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: onManageAccess,
                        icon: const Icon(Icons.group_outlined, size: 18),
                      ),
                    if (!ownerManaged)
                      IconButton(
                        tooltip: 'Slett mappe',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline, size: 18, color: DriftProTheme.error),
                      ),
                  ],
                ),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
                if (docCount > 0)
                  Text(
                    '$docCount ${docCount == 1 ? "fil" : "filer"}',
                    style: TextStyle(fontSize: 10, color: PartnerUi.mutedText(context)),
                  ),
                if (ownerManaged) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      'Bedrift',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFE65100)),
                    ),
                  ),
                ] else if (shared) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F4FF),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      'Felles',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF1D4ED8)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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

    final selected = _selectedDocIds.contains(d.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: PartnerUi.surface(context),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        border: Border.all(
          color: selected
              ? DriftProTheme.primaryGreen
              : (accent ?? Colors.grey).withValues(alpha: 0.22),
          width: selected ? 2 : 1,
        ),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: ListTile(
        leading: _selectMode
            ? Checkbox(
                value: selected,
                activeColor: DriftProTheme.primaryGreen,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedDocIds.add(d.id);
                    } else {
                      _selectedDocIds.remove(d.id);
                    }
                  });
                },
              )
            : Container(
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
        trailing: _selectMode
            ? null
            : PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'open') {
                    await _open(d);
                  } else if (v == 'delete') {
                    await _deleteDocuments([d.id]);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'open', child: Text('Åpne / last ned')),
                  PopupMenuItem(value: 'delete', child: Text('Slett permanent')),
                ],
              ),
        onTap: () {
          if (_selectMode) {
            setState(() {
              if (selected) {
                _selectedDocIds.remove(d.id);
              } else {
                _selectedDocIds.add(d.id);
              }
            });
          } else {
            _open(d);
          }
        },
        onLongPress: _selectMode
            ? null
            : () {
                setState(() {
                  _selectMode = true;
                  _selectedDocIds.add(d.id);
                });
              },
      ),
    );
  }
}
