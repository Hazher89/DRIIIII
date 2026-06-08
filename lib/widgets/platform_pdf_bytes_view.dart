import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Scrollbar visning av alle PDF-sider (ikke bare forsiden).
class PlatformPdfBytesView extends StatelessWidget {
  const PlatformPdfBytesView({
    super.key,
    required this.bytes,
    this.fileName,
  });

  final Uint8List bytes;
  final String? fileName;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width;
    return PdfPreview(
      build: (_) async => bytes,
      pdfFileName: fileName ?? 'dokument.pdf',
      allowPrinting: false,
      allowSharing: false,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      useActions: false,
      maxPageWidth: maxWidth > 32 ? maxWidth - 16 : maxWidth,
      scrollViewDecoration: const BoxDecoration(color: Color(0xFFF4F7F5)),
      pdfPreviewPageDecoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}
