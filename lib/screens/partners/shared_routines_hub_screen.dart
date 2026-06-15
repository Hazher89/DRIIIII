import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import '../../models/partner/shared_partner_document.dart';
import '../../widgets/driftpro_loading_indicator.dart';
import 'widgets/shared_document_notify_dialog.dart';

class SharedRoutinesHubScreen extends StatefulWidget {
  final bool canManage;
  final bool embedded;

  const SharedRoutinesHubScreen({
    super.key,
    this.canManage = false,
    this.embedded = false,
  });

  @override
  State<SharedRoutinesHubScreen> createState() => _SharedRoutinesHubScreenState();
}

class _SharedRoutinesHubScreenState extends State<SharedRoutinesHubScreen> {
  static const _defaultProcedureTitle = 'Retur av litiumbatterier (standard prosedyre)';
  static const _defaultProcedureUrl =
      'https://raw.githubusercontent.com/Hazher89/DRIIIII/main/docs/Retur%20av%20litiumbatterier.pdf';

  bool _loading = true;
  String? _error;
  String? _companyId;
  List<SharedPartnerDocument> _docs = const [];
  List<Partner> _partners = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) {
        throw Exception('Fant ikke bedrift for bruker.');
      }
      final list = await PartnerService.fetchSharedPartnerDocuments(companyId: cid);
      final partners = await PartnerService.fetchPartners(companyId: cid);
      if (!mounted) return;
      setState(() {
        _companyId = cid;
        _docs = list;
        _partners = partners.where((p) => p.isActive).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _open(SharedPartnerDocument doc) async {
    try {
      final url = await PartnerService.resolveStorageUrl(doc.storagePath);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke åpne dokument: $e')),
      );
    }
  }

  Future<void> _upload() async {
    if (!widget.canManage || _companyId == null) return;
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'doc', 'docx', 'txt', 'png', 'jpg', 'jpeg'],
    );
    if (picked == null || picked.files.isEmpty) return;
    if (!mounted) return;

    final notifyPlan = await showSharedDocumentNotifyDialog(
      context,
      partners: _partners,
      fileCount: picked.files.length,
    );
    if (!mounted || notifyPlan == null) return;

    setState(() => _loading = true);
    var uploaded = 0;
    var smsQueued = 0;
    var emailQueued = 0;
    var partnersNotified = 0;
    String? lastError;

    try {
      for (var i = 0; i < picked.files.length; i++) {
        final f = picked.files[i];
        final bytes =
            f.bytes ?? (!kIsWeb && f.path != null ? await File(f.path!).readAsBytes() : null);
        if (bytes == null || bytes.isEmpty) continue;

        final safeName = f.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final storagePath =
            'company_${_companyId!}/partner_shared_routines/${DateTime.now().millisecondsSinceEpoch}_$safeName';
        final mime = _guessMime(f.name);
        try {
          final storedPath = await PartnerService.uploadPartnerDocumentFile(
            storagePath: storagePath,
            bytes: Uint8List.fromList(bytes),
            mimeType: mime,
          );
          final created = await PartnerService.addSharedPartnerDocument(
            SharedPartnerDocument(
              id: '',
              companyId: _companyId!,
              title: f.name,
              storagePath: storedPath,
              fileName: f.name,
              mimeType: mime,
              category: 'procedure',
              createdAt: DateTime.now(),
            ),
          );
          uploaded++;

          if (notifyPlan.willNotify) {
            final stats = await PartnerService.notifySharedPartnerDocumentUpload(
              documentId: created.id,
              partnerIds: notifyPlan.partnerIds.toList(),
              channel: sharedDocumentNotifyChannelDb(notifyPlan.channel),
            );
            smsQueued += (stats['sms'] as num?)?.toInt() ?? 0;
            emailQueued += (stats['email'] as num?)?.toInt() ?? 0;
            partnersNotified += (stats['partners'] as num?)?.toInt() ?? 0;
          }
        } catch (e) {
          lastError = '$e';
        }
      }

      if (notifyPlan.willNotify && smsQueued > 0) {
        await PartnerService.flushSmsOutbox();
      }
    } finally {
      await _load();
    }

    if (!mounted) return;
    if (uploaded == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opplasting feilet${lastError != null ? ': $lastError' : ''}'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final parts = <String>[
      uploaded == 1 ? '1 dokument lastet opp' : '$uploaded dokumenter lastet opp',
    ];
    if (notifyPlan.willNotify) {
      if (smsQueued > 0 && emailQueued > 0) {
        parts.add('$smsQueued SMS og $emailQueued e-post i kø');
      } else if (smsQueued > 0) {
        parts.add('$smsQueued SMS i kø');
      } else if (emailQueued > 0) {
        parts.add('$emailQueued e-post i kø');
      } else {
        parts.add('ingen varsler i kø (sjekk kontaktinfo hos partner)');
      }
      if (partnersNotified > 0) {
        parts.add('til $partnersNotified bedrift(er)');
      }
    } else {
      parts.add('uten varsel');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(parts.join(' · '))),
    );
  }

  Future<void> _delete(SharedPartnerDocument doc) async {
    if (!widget.canManage) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett dokument?'),
        content: Text('Slette «${doc.title}» fra felles rutiner/prosedyrer?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await PartnerService.deleteSharedPartnerDocument(doc.id);
    await _load();
  }

  String _guessMime(String name) {
    final ext = name.split('.').length > 1 ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
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
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  Widget build(BuildContext context) {
    final sharedInfo = Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DriftProTheme.primaryGreen.withValues(alpha: 0.25),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Felles mappe delt med alle samarbeidspartnere i bedriften og superadmin.',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
        ],
      ),
    );

    final content = _loading
        ? const DriftProLoadingCenter()
        : _error != null
            ? Center(child: Text(_error!))
            : _docs.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Ingen rutiner/prosedyrer delt ennå.\nTrykk «Last opp rutine/prosedyre».',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final d = _docs[i];
                      final lower = (d.fileName ?? '').toLowerCase();
                      final icon = lower.endsWith('.pdf')
                          ? Icons.picture_as_pdf_outlined
                          : lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg')
                              ? Icons.image_outlined
                              : Icons.description_outlined;
                      return Card(
                        child: ListTile(
                          leading: Icon(icon, color: DriftProTheme.primaryGreen),
                          title: Text(d.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(d.fileName ?? d.storagePath),
                          onTap: () => _open(d),
                          trailing: widget.canManage
                              ? IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () => _delete(d),
                                )
                              : const Icon(Icons.open_in_new),
                        ),
                      );
                    },
                  );

    final defaultProcedureCard = Card(
      color: DriftProTheme.primaryGreen.withValues(alpha: 0.06),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ListTile(
        leading: const Icon(Icons.picture_as_pdf_outlined, color: DriftProTheme.primaryGreen),
        title: const Text(
          _defaultProcedureTitle,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text('Felles standard dokument'),
        trailing: const Icon(Icons.open_in_new),
        onTap: () => launchUrl(Uri.parse(_defaultProcedureUrl), mode: LaunchMode.externalApplication),
      ),
    );

    if (widget.embedded) {
      return Column(
        children: [
          sharedInfo,
          if (widget.canManage)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _upload,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Last opp rutine/prosedyre'),
                ),
              ),
            ),
          defaultProcedureCard,
          Expanded(child: content),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rutiner og prosedyrer'),
        actions: [
          if (widget.canManage)
            IconButton(
              tooltip: 'Last opp',
              onPressed: _upload,
              icon: const Icon(Icons.upload_file),
            ),
          IconButton(
            tooltip: 'Oppdater',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          sharedInfo,
          defaultProcedureCard,
          Expanded(child: content),
        ],
      ),
    );
  }
}
