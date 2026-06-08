import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/storage/company_file_storage.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/risk_assessment.dart';
import '../../../../widgets/resolved_storage_image.dart';
import '../../../../widgets/driftpro_loading_indicator.dart';

/// Opplasting og visning av bilder og dokumenter for risikoanalyser.
class RiskAssessmentAttachmentsPanel extends StatelessWidget {
  final List<String> imageUrls;
  final List<RiskDocumentAttachment> documents;
  final bool readOnly;
  final bool uploading;
  final ValueChanged<List<String>>? onImagesChanged;
  final ValueChanged<List<RiskDocumentAttachment>>? onDocumentsChanged;
  final Future<void> Function(List<PlatformFile> files, bool isImage)? onUpload;

  const RiskAssessmentAttachmentsPanel({
    super.key,
    required this.imageUrls,
    this.documents = const [],
    this.readOnly = false,
    this.uploading = false,
    this.onImagesChanged,
    this.onDocumentsChanged,
    this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Vedlegg', style: DriftProTheme.labelLg),
            if (uploading) ...[
              const SizedBox(width: 12),
              SizedBox(width: 18, height: 18, child: DriftProLoadingIndicator(size: 18)),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Last opp bilder (f.eks. foto av arbeidsplass) og dokumenter (PDF, Word, Excel).',
          style: DriftProTheme.caption,
        ),
        const SizedBox(height: 12),
        if (!readOnly && onUpload != null) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: uploading ? null : () => _pick(context, imageOnly: true),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Legg til bilder'),
              ),
              OutlinedButton.icon(
                onPressed: uploading ? null : () => _pick(context, imageOnly: false),
                icon: const Icon(Icons.attach_file),
                label: const Text('Legg til dokumenter'),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (imageUrls.isNotEmpty) ...[
          Text('Bilder (${imageUrls.length})', style: DriftProTheme.labelSm),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: imageUrls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _imageTile(context, imageUrls[i], i, isDark),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (documents.isNotEmpty) ...[
          Text('Dokumenter (${documents.length})', style: DriftProTheme.labelSm),
          const SizedBox(height: 8),
          ...documents.asMap().entries.map(
                (e) => _documentTile(context, e.value, e.key, isDark),
              ),
        ],
        if (imageUrls.isEmpty && documents.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? DriftProTheme.cardDark : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
              ),
            ),
            child: Column(
              children: [
                Icon(Icons.cloud_upload_outlined, size: 36, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Text(
                  readOnly ? 'Ingen vedlegg' : 'Ingen vedlegg ennå',
                  style: DriftProTheme.bodySm.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, {required bool imageOnly}) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: imageOnly ? FileType.image : FileType.custom,
      allowedExtensions: imageOnly
          ? null
          : ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'png', 'jpg', 'jpeg'],
    );
    if (result == null || onUpload == null) return;
    await onUpload!(result.files, imageOnly);
  }

  Widget _imageTile(BuildContext context, String url, int index, bool isDark) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ResolvedStorageImage(
            storageRef: url,
            width: 100,
            height: 100,
            fit: BoxFit.cover,
          ),
        ),
        if (!readOnly)
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () {
                final next = List<String>.from(imageUrls)..removeAt(index);
                onImagesChanged?.call(next);
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }

  Widget _documentTile(
    BuildContext context,
    RiskDocumentAttachment doc,
    int index,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          doc.isPdf ? Icons.picture_as_pdf : Icons.description_outlined,
          color: DriftProTheme.accentBlue,
        ),
        title: Text(doc.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: doc.mimeType != null ? Text(doc.mimeType!, style: DriftProTheme.caption) : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 20),
              onPressed: () => _openUrl(doc.url),
            ),
            if (!readOnly)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                onPressed: () {
                  final next = List<RiskDocumentAttachment>.from(documents)..removeAt(index);
                  onDocumentsChanged?.call(next);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final resolved = await CompanyFileStorage.resolveDisplayUrl(url);
    final uri = Uri.tryParse(resolved);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
