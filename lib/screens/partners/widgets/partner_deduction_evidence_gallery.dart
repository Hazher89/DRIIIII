import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/partner/partner_deduction_service.dart';
import '../../../core/services/storage/company_file_storage.dart';
import '../../../core/theme/driftpro_theme_context.dart';
import '../../../models/partner/partner_deduction_evidence.dart';
import '../../../widgets/resolved_storage_image.dart';
import 'partner_modern_ui.dart';

/// Viser bilde/video-bevis for en bot/trekk-sak.
class PartnerDeductionEvidenceGallery extends StatefulWidget {
  const PartnerDeductionEvidenceGallery({
    super.key,
    required this.caseId,
    this.compact = false,
  });

  final String caseId;
  final bool compact;

  @override
  State<PartnerDeductionEvidenceGallery> createState() =>
      _PartnerDeductionEvidenceGalleryState();
}

class _PartnerDeductionEvidenceGalleryState extends State<PartnerDeductionEvidenceGallery> {
  List<PartnerDeductionEvidence>? _items;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await PartnerDeductionService.listEvidence(widget.caseId);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _open(PartnerDeductionEvidence e) async {
    final url = await CompanyFileStorage.resolveDisplayUrl(e.storageRef);
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _previewImage(BuildContext context, PartnerDeductionEvidence e) async {
    final url = await CompanyFileStorage.resolveDisplayUrl(e.storageRef);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(e.fileName, style: const TextStyle(fontSize: 14)),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    final items = _items ?? [];
    if (items.isEmpty) {
      return Text(
        'Ingen vedlegg',
        style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
      );
    }

    final tileSize = widget.compact ? 64.0 : 88.0;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in items)
          InkWell(
            onTap: () => e.isVideo ? _open(e) : _previewImage(context, e),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: tileSize,
              height: tileSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: PartnerModernUi.border(context)),
                color: context.driftColors.surfaceMuted,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (e.isImage)
                      ResolvedStorageImage(storageRef: e.storageRef, fit: BoxFit.cover)
                    else
                      ColoredBox(
                        color: Colors.black87,
                        child: Icon(
                          Icons.videocam_rounded,
                          color: Colors.white.withValues(alpha: 0.9),
                          size: 28,
                        ),
                      ),
                    Positioned(
                      left: 4,
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          e.isVideo ? 'Video' : 'Bilde',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (!widget.compact)
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Oppdater bevis'),
          ),
      ],
    );
  }
}
