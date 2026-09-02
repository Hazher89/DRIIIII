import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/company_principals.dart';
import '../../core/services/storage/company_file_storage.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/storage_path_sanitizer.dart';
import '../../models/user_profile.dart';
import '../../models/whistleblowing_report.dart';
import '../../widgets/common/team_equal_controls.dart';
import '../../widgets/driftpro_loading_indicator.dart';
import '../../widgets/resolved_storage_image.dart';

class WhistleblowingScreen extends StatefulWidget {
  const WhistleblowingScreen({super.key});

  @override
  State<WhistleblowingScreen> createState() => _WhistleblowingScreenState();
}

class _WhistleblowingScreenState extends State<WhistleblowingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  final List<_PendingAttachment> _attachments = [];
  bool _isSubmitting = false;
  bool _loadingInbox = false;
  UserProfile? _profile;
  List<WhistleblowingReport> _inbox = const [];
  final Set<WhistlePrincipal> _recipients = {
    WhistlePrincipal.tommy,
    WhistlePrincipal.nico,
    WhistlePrincipal.hazher,
  };

  bool get _isPrincipal {
    final p = _profile;
    return p != null && CompanyPrincipal.isPrincipal(p);
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final profile = await SupabaseService.fetchCurrentUserProfile();
    if (!mounted) return;
    setState(() => _profile = profile);
    if (profile != null && CompanyPrincipal.isPrincipal(profile)) {
      await _loadInbox();
    }
  }

  Future<void> _loadInbox() async {
    setState(() => _loadingInbox = true);
    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId == null) return;
      final rows =
          await SupabaseService.fetchWhistleblowingReports(companyId);
      if (!mounted) return;
      setState(() => _inbox = rows);
    } catch (_) {
      // Inbox er valgfri — sending skal fortsatt fungere.
    } finally {
      if (mounted) setState(() => _loadingInbox = false);
    }
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;

    final added = <_PendingAttachment>[];
    for (final f in result.files) {
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      final name = (f.name.trim().isEmpty) ? 'vedlegg' : f.name.trim();
      added.add(
        _PendingAttachment(
          bytes: bytes,
          name: name,
          extension: f.extension,
        ),
      );
    }
    if (added.isEmpty) return;
    setState(() => _attachments.addAll(added));
  }

  void _toggle(WhistlePrincipal p) {
    setState(() {
      if (_recipients.contains(p)) {
        if (_recipients.length > 1) _recipients.remove(p);
      } else {
        _recipients.add(p);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _recipients
        ..clear()
        ..addAll(WhistlePrincipal.values);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_recipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg minst én mottaker')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId == null) throw Exception('Kunne ikke finne selskap-ID');

      final attachmentRefs = <String>[];
      for (final file in _attachments) {
        final safeName = StoragePathSanitizer.fileName(file.name);
        final fileName = '${const Uuid().v4()}_$safeName';
        final path = 'whistleblowing/$companyId/$fileName';
        final stored = await CompanyFileStorage.upload(
          supabaseBucket: 'tickets',
          storagePath: path,
          bytes: file.bytes,
          category: 'whistleblowing',
          fileName: fileName,
        );
        attachmentRefs.add(CompanyFileStorage.toStorageReference(stored));
      }

      final selected = WhistlePrincipal.values
          .where(_recipients.contains)
          .toList();

      await SupabaseService.createWhistleblowingReport(
        WhistleblowingReport(
          id: '',
          companyId: companyId,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          imageUrls: attachmentRefs,
          recipientPrincipals: selected,
        ),
      );

      if (!mounted) return;
      final names = selected.map((p) => p.label).join(', ');
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Anmeldelse sendt'),
          content: Text(
            'Din anmeldelse er sendt helt anonymt til:\n\n$names',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Feil ved sending: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _openAttachment(String storageRef) async {
    try {
      final url = await CompanyFileStorage.resolveDisplayUrl(storageRef);
      final uri = Uri.tryParse(url);
      if (uri == null) throw Exception('Ugyldig lenke');
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kunne ikke åpne vedlegget')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke åpne vedlegg: $e')),
        );
      }
    }
  }

  void _showReport(WhistleblowingReport report) {
    final date = report.createdAt == null
        ? ''
        : DateFormat('dd.MM.yyyy HH:mm').format(report.createdAt!.toLocal());
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, controller) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  report.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (date.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(date, style: DriftProTheme.caption),
                ],
                const SizedBox(height: 8),
                Text(
                  'Mottakere: ${report.recipientPrincipals.map((p) => p.label).join(', ')}',
                  style: DriftProTheme.caption,
                ),
                const SizedBox(height: 16),
                Text(
                  report.description,
                  style: const TextStyle(height: 1.45),
                ),
                const SizedBox(height: 20),
                Text(
                  'Vedlegg (${report.imageUrls.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                if (report.imageUrls.isEmpty)
                  Text(
                    'Ingen vedlegg',
                    style: DriftProTheme.caption,
                  )
                else
                  ...report.imageUrls.map(
                    (ref) => _StoredAttachmentTile(
                      storageRef: ref,
                      isDark: isDark,
                      onOpen: () => _openAttachment(ref),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.bgDark : DriftProTheme.bgLight,
      appBar: AppBar(title: const Text('Anonym anmeldelse')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isPrincipal) ...[
                _buildInbox(isDark),
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 20),
                Text(
                  'Send ny anmeldelse',
                  style: DriftProTheme.labelLg.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.security, color: Colors.amber),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Hei — jeg er DriftPro. Hazher, som har skapt meg, har vært '
                        'knallhardt mot meg på én ting: jeg får aldri vise hvem som '
                        'sender her. Punktum. Så pust ut, velg mottaker, og si det '
                        'som må sies. Anonymiteten er låst — du kan trygt informere '
                        'den du ønsker.',
                        style: TextStyle(fontSize: 13, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Hvem skal motta?',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: _selectAll,
                    child: const Text('Velg alle'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Velg én, flere eller alle tre.',
                style: DriftProTheme.caption,
              ),
              const SizedBox(height: 12),
              ...WhistlePrincipal.values.map((p) {
                final selected = _recipients.contains(p);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: selected
                        ? DriftProTheme.primaryGreen.withValues(alpha: 0.1)
                        : (isDark ? DriftProTheme.cardDark : Colors.white),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => _toggle(p),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        constraints: const BoxConstraints(
                          minHeight: TeamControlMetrics.height + 12,
                        ),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? DriftProTheme.primaryGreen
                                : Colors.grey.shade300,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              color: selected
                                  ? DriftProTheme.primaryGreen
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.label,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: selected
                                          ? DriftProTheme.primaryGreen
                                          : null,
                                    ),
                                  ),
                                  Text(p.title, style: DriftProTheme.caption),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 24),
              const Text(
                'Hva gjelder saken?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  hintText: 'Tittel på saken',
                  filled: true,
                  fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty ? 'Påkrevd' : null,
              ),
              const SizedBox(height: 24),
              const Text(
                'Beskriv saken i detalj',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: 'Skriv her...',
                  filled: true,
                  fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty ? 'Påkrevd' : null,
              ),
              const SizedBox(height: 24),
              const Text(
                'Vedlegg (valgfritt)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Bilder, PDF, Word, Excel, video — lagres trygt i Dropbox.',
                style: DriftProTheme.caption,
              ),
              const SizedBox(height: 12),
              _buildAttachmentPicker(isDark),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: TeamControlMetrics.height + 8,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DriftProTheme.error,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Send anmeldelse anonymt',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInbox(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Mottatte anmeldelser',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            IconButton(
              tooltip: 'Oppdater',
              onPressed: _loadingInbox ? null : _loadInbox,
              icon: _loadingInbox
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: DriftProLoadingIndicator(size: 18),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Kun du og de andre i ledelsen ser disse. Åpne for å lese og se vedlegg.',
          style: DriftProTheme.caption,
        ),
        const SizedBox(height: 12),
        if (_loadingInbox && _inbox.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: DriftProLoadingCenter(),
          )
        else if (_inbox.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? DriftProTheme.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              'Ingen anmeldelser ennå.',
              style: DriftProTheme.caption,
            ),
          )
        else
          ..._inbox.map((r) {
            final date = r.createdAt == null
                ? ''
                : DateFormat('dd.MM.yy HH:mm').format(r.createdAt!.toLocal());
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: ListTile(
                onTap: () => _showReport(r),
                title: Text(
                  r.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  [
                    if (date.isNotEmpty) date,
                    if (r.imageUrls.isNotEmpty)
                      '${r.imageUrls.length} vedlegg',
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildAttachmentPicker(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_attachments.isNotEmpty) ...[
          ..._attachments.asMap().entries.map((entry) {
            final i = entry.key;
            final file = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: isDark ? DriftProTheme.cardDark : Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    leading: file.isImage
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              file.bytes,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.broken_image_outlined,
                              ),
                            ),
                          )
                        : CircleAvatar(
                            backgroundColor:
                                DriftProTheme.accentBlue.withValues(alpha: 0.12),
                            child: Icon(
                              file.icon,
                              color: DriftProTheme.accentBlue,
                            ),
                          ),
                    title: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      file.sizeLabel,
                      style: DriftProTheme.caption,
                    ),
                    trailing: IconButton(
                      tooltip: 'Fjern',
                      onPressed: () =>
                          setState(() => _attachments.removeAt(i)),
                      icon: const Icon(Icons.close, color: Colors.red),
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 4),
        ],
        InkWell(
          onTap: _isSubmitting ? null : _pickAttachments,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: isDark ? DriftProTheme.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
            ),
            child: const Column(
              children: [
                Icon(Icons.attach_file, color: Colors.grey, size: 32),
                SizedBox(height: 8),
                Text(
                  'Trykk for å legge til vedlegg',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PendingAttachment {
  final Uint8List bytes;
  final String name;
  final String? extension;

  const _PendingAttachment({
    required this.bytes,
    required this.name,
    this.extension,
  });

  String get _ext => (extension ?? _extFromName).toLowerCase();

  String get _extFromName {
    final i = name.lastIndexOf('.');
    if (i < 0 || i == name.length - 1) return '';
    return name.substring(i + 1);
  }

  bool get isImage =>
      const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp'}
          .contains(_ext);

  bool get isPdf => _ext == 'pdf';

  IconData get icon {
    if (isPdf) return Icons.picture_as_pdf;
    if (const {'doc', 'docx'}.contains(_ext)) return Icons.description_outlined;
    if (const {'xls', 'xlsx', 'csv'}.contains(_ext)) {
      return Icons.table_chart_outlined;
    }
    if (const {'mp4', 'mov', 'm4v', 'avi'}.contains(_ext)) {
      return Icons.videocam_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  String get sizeLabel {
    final kb = bytes.length / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

class _StoredAttachmentTile extends StatelessWidget {
  final String storageRef;
  final bool isDark;
  final VoidCallback onOpen;

  const _StoredAttachmentTile({
    required this.storageRef,
    required this.isDark,
    required this.onOpen,
  });

  String get _fileName {
    final raw = storageRef
        .replaceFirst('dropbox://', '')
        .split('?')
        .first
        .split('/')
        .where((p) => p.isNotEmpty)
        .lastOrNull;
    if (raw == null || raw.isEmpty) return 'Vedlegg';
    final uuidPrefix = RegExp(
      r'^[0-9a-fA-F-]{8,}_',
    );
    return raw.replaceFirst(uuidPrefix, '');
  }

  bool get _isImage {
    final lower = _fileName.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ListTile(
        onTap: onOpen,
        leading: _isImage
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ResolvedStorageImage(
                  storageRef: storageRef,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                ),
              )
            : const Icon(Icons.insert_drive_file_outlined),
        title: Text(
          _fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: const Text('Trykk for å åpne'),
        trailing: const Icon(Icons.open_in_new, size: 18),
      ),
    );
  }
}
