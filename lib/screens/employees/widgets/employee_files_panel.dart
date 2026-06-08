import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/hms/employee_document_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/hms_document.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/resolved_storage_image.dart';
import '../../../core/services/storage/company_file_storage.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Filer for én ansatt — opplasting, synlighet for ansatt, oversikt.
class EmployeeFilesPanel extends StatefulWidget {
  final UserProfile employee;
  final UserProfile currentUser;
  final bool canUpload;
  final bool canManageVisibility;

  const EmployeeFilesPanel({
    super.key,
    required this.employee,
    required this.currentUser,
    this.canUpload = false,
    this.canManageVisibility = false,
  });

  @override
  State<EmployeeFilesPanel> createState() => _EmployeeFilesPanelState();
}

class _EmployeeFilesPanelState extends State<EmployeeFilesPanel> {
  List<HmsDocument> _docs = [];
  bool _loading = true;
  String _filter = 'alle';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _docs = await EmployeeDocumentService.fetchForUser(
        userId: widget.employee.id,
        companyId: widget.employee.companyId,
        employeeVisibleOnly: !widget.canManageVisibility,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<HmsDocument> get _filtered {
    switch (_filter) {
      case 'synlig':
        return _docs.where((d) => d.employeeVisible).toList();
      case 'kurs':
        return _docs
            .where((d) =>
                d.documentType == HmsDocumentType.kursbevis ||
                d.documentType == HmsDocumentType.sertifikat)
            .toList();
      case 'bilder':
        return _docs.where((d) {
          final n = (d.fileName ?? d.fileUrl).toLowerCase();
          return n.endsWith('.jpg') ||
              n.endsWith('.jpeg') ||
              n.endsWith('.png') ||
              n.endsWith('.webp');
        }).toList();
      default:
        return _docs;
    }
  }

  Future<void> _upload() async {
    final companyId = widget.employee.companyId;
    if (companyId == null) return;

    final titleCtrl = TextEditingController();
    var type = HmsDocumentType.annet;
    var employeeVisible = false;
    DateTime? expires;

    final metaOk = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Last opp fil'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Tittel *'),
                ),
                DropdownButtonFormField<HmsDocumentType>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: HmsDocumentType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                      .toList(),
                  onChanged: (v) => setD(() => type = v ?? HmsDocumentType.annet),
                ),
                if (widget.canManageVisibility)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ansatt kan se filen'),
                    subtitle: const Text('Vises i personalmappe for ansatt'),
                    value: employeeVisible,
                    onChanged: (v) => setD(() => employeeVisible = v),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Utløpsdato (valgfritt)'),
                  subtitle: Text(
                    expires != null
                        ? '${expires!.day}.${expires!.month}.${expires!.year}'
                        : 'Ikke satt',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(days: 365)),
                      firstDate: DateTime(2020),
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

    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
    );
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
        userId: widget.employee.id,
        fileName: f.name,
        bytes: f.bytes!,
      );
      await EmployeeDocumentService.uploadForEmployee(
        userId: widget.employee.id,
        companyId: companyId,
        uploadedBy: widget.currentUser.id,
        type: type,
        title: titleCtrl.text.trim(),
        fileUrl: url,
        fileName: f.name,
        fileSize: f.size,
        expiresAt: expires,
        employeeVisible: employeeVisible,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fil lastet opp')),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final visibleCount = _docs.where((d) => d.employeeVisible).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              _chip('alle', 'Alle (${_docs.length})'),
              const SizedBox(width: 6),
              _chip('synlig', 'Synlig ($visibleCount)'),
              const SizedBox(width: 6),
              _chip('kurs', 'Kurs'),
              const SizedBox(width: 6),
              _chip('bilder', 'Bilder'),
            ],
          ),
        ),
        if (widget.canManageVisibility)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Kun filer med «Ansatt kan se» vises i ansattens personalmappe.',
                      style: DriftProTheme.caption,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: _loading
              ? const DriftProLoadingCenter()
              : _filtered.isEmpty
                  ? Center(
                      child: Text(
                        'Ingen filer',
                        style: DriftProTheme.caption,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) => _docTile(_filtered[i], isDark),
                      ),
                    ),
        ),
        if (widget.canUpload)
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _upload,
              icon: const Icon(Icons.upload_file),
              label: const Text('Last opp fil / bilde / PDF'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),
      ],
    );
  }

  Widget _chip(String id, String label) {
    final sel = _filter == id;
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: sel,
      onSelected: (_) => setState(() => _filter = id),
    );
  }

  Widget _docTile(HmsDocument d, bool isDark) {
    final isImage = (d.fileName ?? d.fileUrl).toLowerCase().contains(RegExp(r'\.(jpg|jpeg|png|webp)$'));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: isImage
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ResolvedStorageImage(
                  storageRef: d.fileUrl,
                  width: 48,
                  height: 48,
                ),
              )
            : Icon(
                d.fileName?.endsWith('.pdf') == true ? Icons.picture_as_pdf : Icons.insert_drive_file,
                color: DriftProTheme.primaryGreen,
              ),
        title: Text(d.title),
        subtitle: Text(
          '${d.documentType.label}'
          '${d.expiresAt != null ? ' · utløper ${d.expiresAt!.day}.${d.expiresAt!.month}.${d.expiresAt!.year}' : ''}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.canManageVisibility)
              Icon(
                d.employeeVisible ? Icons.visibility : Icons.visibility_off,
                size: 20,
                color: d.employeeVisible ? DriftProTheme.primaryGreen : Colors.grey,
              ),
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 20),
              onPressed: () async {
                final url = await CompanyFileStorage.resolveDisplayUrl(d.fileUrl);
                await launchUrl(Uri.parse(url));
              },
            ),
            if (widget.canManageVisibility)
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'toggle') {
                    await EmployeeDocumentService.setEmployeeVisible(
                      documentId: d.id,
                      visible: !d.employeeVisible,
                    );
                    _load();
                  } else if (v == 'delete') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Slett fil?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Nei')),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                            child: const Text('Slett'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await EmployeeDocumentService.deleteDocument(d.id);
                      _load();
                    }
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(d.employeeVisible ? 'Skjul for ansatt' : 'Vis for ansatt'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('Slett')),
                ],
              ),
          ],
        ),
        onTap: widget.canManageVisibility
            ? () async {
                await EmployeeDocumentService.setEmployeeVisible(
                  documentId: d.id,
                  visible: !d.employeeVisible,
                );
                _load();
              }
            : null,
      ),
    );
  }
}
