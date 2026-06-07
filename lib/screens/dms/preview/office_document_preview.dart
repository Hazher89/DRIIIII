import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../widgets/platform_office_view.dart';

/// Viser Office-dokumenter med original layout (Word/PowerPoint).
class OfficeDocumentPreview extends StatelessWidget {
  final String url;
  final Uint8List bytes;
  final String? extension;

  const OfficeDocumentPreview({
    super.key,
    required this.url,
    required this.bytes,
    this.extension,
  });

  bool get _isDocx => extension?.toLowerCase() == 'docx';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: const Color(0xFF2B579A),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: const Row(
            children: [
              Icon(Icons.description, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Dokumentvisning',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: PlatformOfficeView(
            url: url,
            bytes: _isDocx ? bytes : null,
            extension: extension,
          ),
        ),
      ],
    );
  }
}
