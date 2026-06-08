import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/services/hms/hms_pdf_export_service.dart';

/// Standard «Last ned PDF»-knapp for HMS-detaljskjermer.
class HmsPdfExportButton extends StatelessWidget {
  final Future<Uint8List> Function() onGenerate;
  final String fileName;
  final String tooltip;

  const HmsPdfExportButton({
    super.key,
    required this.onGenerate,
    required this.fileName,
    this.tooltip = 'Last ned PDF',
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.picture_as_pdf_outlined),
      tooltip: tooltip,
      onPressed: () => HmsPdfExportService.runWithFeedback(
        context,
        generate: onGenerate,
        fileName: fileName,
      ),
    );
  }
}
