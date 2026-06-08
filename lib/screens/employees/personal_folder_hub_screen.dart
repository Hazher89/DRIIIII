import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/hms/employee_document_service.dart';
import '../../core/services/storage/company_file_storage.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/hms_document.dart';
import '../../models/user_profile.dart';
import '../../widgets/resolved_storage_image.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Avansert personalmappe — oversikt, søk, opplasting og redigering.
class PersonalFolderHubScreen extends StatefulWidget {
  const PersonalFolderHubScreen({super.key});

  @override
  State<PersonalFolderHubScreen> createState() => _PersonalFolderHubScreenState();
}

class _PersonalFolderHubScreenState extends State<PersonalFolderHubScreen> {
  UserProfile? _me;
  List<HmsDocument> _docs = [];
  bool _loading = true;
  String _query = '';
  String _filter = 'alle';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await SupabaseService.fetchCurrentUserProfile();
      if (p == null) return;
      final docs = await EmployeeDocumentService.fetchForUser(
        userId: p.id,
        companyId: p.companyId,
        employeeVisibleOnly: true,
      );
      if (mounted) {
        setState(() {
          _me = p;
          _docs = docs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<HmsDocument> get _filtered {
    var list = _docs;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((d) {
        final blob =
            '${d.title} ${d.description ?? ''} ${d.documentType.label} ${d.fileName ?? ''} ${d.tags.join(' ')}'
                .toLowerCase();
        return blob.contains(q);
      }).toList();
    }
    switch (_filter) {
      case 'kurs':
        return list
            .where((d) =>
                d.documentType == HmsDocumentType.kursbevis ||
                d.documentType == HmsDocumentType.sertifikat)
            .toList();
      case 'avtale':
        return list
            .where((d) => d.documentType == HmsDocumentType.arbeidsavtale)
            .toList();
      case 'hms':
        return list
            .where((d) => d.documentType == HmsDocumentType.hms_dokument)
            .toList();
      case 'bilder':
        return list.where((d) => _isImage(d)).toList();
      case 'pdf':
        return list.where((d) => _isPdf(d)).toList();
      case 'utloper':
        return list.where((d) => d.isExpired || d.expiresSoon).toList();
      default:
        return list;
    }
  }

  bool _isImage(HmsDocument d) {
    final n = (d.fileName ?? d.fileUrl).toLowerCase();
    return n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.png') ||
        n.endsWith('.webp');
  }

  bool _isPdf(HmsDocument d) =>
      (d.fileName ?? d.fileUrl).toLowerCase().endsWith('.pdf');

  bool _canEdit(HmsDocument d) => _me != null && d.uploadedBy == _me!.id;

  String _formatSize(int? bytes) {
    if (bytes == null) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stats = EmployeeDocumentService.statsFor(_docs);

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Personalmappe'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _me == null ? null : _upload,
        icon: const Icon(Icons.upload_file),
        label: const Text('Last opp'),
      ),
      body: _loading
          ? const DriftProLoadingCenter()
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: DriftProTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _me?.fullName ?? 'Min mappe',
                                  style: DriftProTheme.headingSm.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Komplett dokumentarkiv — kursbevis, avtaler, '
                                  'sertifikater og filer delt av bedriften. '
                                  'Last opp egne dokumenter og hold oversikt over utløp.',
                                  style: DriftProTheme.bodySm.copyWith(
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _statBox('${stats['total']}', 'Dokumenter', isDark),
                              const SizedBox(width: 8),
                              _statBox('${stats['kurs']}', 'Kurs/sert.', isDark),
                              const SizedBox(width: 8),
                              _statBox(
                                '${stats['expires_soon']}',
                                'Utløper snart',
                                isDark,
                                warn: (stats['expires_soon'] ?? 0) > 0,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              hintText: 'Søk tittel, type, filnavn…',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _query.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: _searchCtrl.clear,
                                    )
                                  : null,
                              filled: true,
                              fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _filterChip('alle', 'Alle'),
                                _filterChip('kurs', 'Kurs'),
                                _filterChip('avtale', 'Avtale'),
                                _filterChip('hms', 'HMS'),
                                _filterChip('bilder', 'Bilder'),
                                _filterChip('pdf', 'PDF'),
                                _filterChip('utloper', 'Utløper'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_filtered.length} av ${_docs.length} dokumenter',
                            style: DriftProTheme.caption,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_filtered.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.folder_open,
                                size: 56,
                                color: isDark ? Colors.white24 : Colors.grey.shade300,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _docs.isEmpty
                                    ? 'Ingen dokumenter ennå'
                                    : 'Ingen treff på filter/søk',
                                style: DriftProTheme.bodyMd,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Trykk «Last opp» for å legge til kursbevis eller annet, '
                                'eller kontakt leder hvis du mangler filer fra bedriften.',
                                textAlign: TextAlign.center,
                                style: DriftProTheme.caption,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _docCard(_filtered[i], isDark),
                          childCount: _filtered.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _statBox(String value, String label, bool isDark, {bool warn = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? DriftProTheme.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: warn
                ? DriftProTheme.warning.withValues(alpha: 0.5)
                : (isDark ? DriftProTheme.dividerDark : Colors.grey.shade200),
          ),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: DriftProTheme.headingSm.copyWith(
                color: warn ? DriftProTheme.warning : DriftProTheme.primaryGreen,
              ),
            ),
            Text(label, style: DriftProTheme.caption),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String id, String label) {
    final sel = _filter == id;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: sel,
        onSelected: (_) => setState(() => _filter = id),
      ),
    );
  }

  Widget _docCard(HmsDocument d, bool isDark) {
    final expired = d.isExpired;
    final soon = d.expiresSoon;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: expired
              ? DriftProTheme.error.withValues(alpha: 0.4)
              : soon
                  ? DriftProTheme.warning.withValues(alpha: 0.4)
                  : (isDark ? DriftProTheme.dividerDark : Colors.grey.shade200),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showDetail(d),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _thumb(d),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.title,
                      style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${d.documentType.label} · ${_formatSize(d.fileSize)}',
                      style: DriftProTheme.caption,
                    ),
                    if (d.expiresAt != null)
                      Text(
                        expired
                            ? 'Utløpt ${DateFormat('d.M.y').format(d.expiresAt!)}'
                            : 'Utløper ${DateFormat('d.M.y').format(d.expiresAt!)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: expired
                              ? DriftProTheme.error
                              : soon
                                  ? DriftProTheme.warning
                                  : null,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (d.updatedAt != null && d.createdAt != null &&
                        d.updatedAt!.difference(d.createdAt!).inMinutes > 1)
                      Text(
                        'Oppdatert ${DateFormat('d.M.y HH:mm').format(d.updatedAt!)}',
                        style: DriftProTheme.caption.copyWith(fontSize: 10),
                      ),
                  ],
                ),
              ),
              if (d.isVerified)
                const Icon(Icons.verified, color: DriftProTheme.primaryGreen, size: 20),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb(HmsDocument d) {
    if (_isImage(d)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ResolvedStorageImage(
          storageRef: d.fileUrl,
          width: 52,
          height: 52,
        ),
      );
    }
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        _isPdf(d) ? Icons.picture_as_pdf : Icons.insert_drive_file,
        color: DriftProTheme.primaryGreen,
      ),
    );
  }

  Future<void> _showDetail(HmsDocument d) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        minChildSize: 0.35,
        builder: (_, scroll) => SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(d.title, style: DriftProTheme.headingSm),
              const SizedBox(height: 8),
              _detailRow('Type', d.documentType.label),
              if (d.fileName != null) _detailRow('Fil', d.fileName!),
              _detailRow('Størrelse', _formatSize(d.fileSize)),
              if (d.description?.isNotEmpty == true)
                _detailRow('Beskrivelse', d.description!),
              if (d.expiresAt != null)
                _detailRow('Utløper', DateFormat('d. MMMM y').format(d.expiresAt!)),
              if (d.createdAt != null)
                _detailRow('Lagt til', DateFormat('d.M.y HH:mm').format(d.createdAt!)),
              if (d.updatedAt != null)
                _detailRow('Sist endret', DateFormat('d.M.y HH:mm').format(d.updatedAt!)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  final url = await CompanyFileStorage.resolveDisplayUrl(d.fileUrl);
                  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Åpne dokument'),
              ),
              if (_canEdit(d)) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _editDocument(d);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Rediger / bytt fil'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w700)),
          ),
          Expanded(child: Text(value, style: DriftProTheme.bodySm)),
        ],
      ),
    );
  }

  Future<void> _upload() async {
    final me = _me;
    final companyId = me?.companyId;
    if (me == null || companyId == null) return;

    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var type = HmsDocumentType.kursbevis;
    DateTime? expires;

    final metaOk = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Nytt dokument'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Tittel *'),
                ),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Beskrivelse'),
                  maxLines: 2,
                ),
                DropdownButtonFormField<HmsDocumentType>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Kategori'),
                  items: HmsDocumentType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                      .toList(),
                  onChanged: (v) => setD(() => type = v ?? HmsDocumentType.annet),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Utløpsdato'),
                  subtitle: Text(
                    expires != null
                        ? DateFormat('d.M.y').format(expires!)
                        : 'Valgfritt',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(days: 365)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2040),
                    );
                    if (d != null) setD(() => expires = d);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, titleCtrl.text.trim().isNotEmpty),
              child: const Text('Velg fil'),
            ),
          ],
        ),
      ),
    );
    if (metaOk != true) return;

    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.single.bytes == null) return;
    final f = picked.files.single;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final url = await EmployeeDocumentService.uploadFile(
        companyId: companyId,
        userId: me.id,
        fileName: f.name,
        bytes: f.bytes!,
      );
      await EmployeeDocumentService.uploadOwn(
        type: type,
        title: titleCtrl.text.trim(),
        fileUrl: url,
        fileName: f.name,
        fileSize: f.size,
        description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        expiresAt: expires,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dokument lagret i personalmappe')),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _editDocument(HmsDocument d) async {
    final titleCtrl = TextEditingController(text: d.title);
    final descCtrl = TextEditingController(text: d.description ?? '');
    var type = d.documentType;
    DateTime? expires = d.expiresAt;
    var replaceFile = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Rediger dokument'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Tittel'),
                ),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Beskrivelse'),
                  maxLines: 2,
                ),
                DropdownButtonFormField<HmsDocumentType>(
                  value: type,
                  items: HmsDocumentType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                      .toList(),
                  onChanged: (v) => setD(() => type = v ?? type),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bytt fil'),
                  value: replaceFile,
                  onChanged: (v) => setD(() => replaceFile = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Lagre'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || _me == null) return;

    String? newUrl;
    String? newName;
    int? newSize;

    if (replaceFile) {
      final picked = await FilePicker.platform.pickFiles(withData: true);
      if (picked == null || picked.files.single.bytes == null) return;
      final f = picked.files.single;
      newUrl = await EmployeeDocumentService.uploadFile(
        companyId: _me!.companyId!,
        userId: _me!.id,
        fileName: f.name,
        bytes: f.bytes!,
      );
      newName = f.name;
      newSize = f.size;
    }

    try {
      await EmployeeDocumentService.updateDocument(
        documentId: d.id,
        title: titleCtrl.text.trim(),
        description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        type: type,
        expiresAt: expires,
        fileUrl: newUrl,
        fileName: newName,
        fileSize: newSize,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dokument oppdatert')),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
