import 'package:flutter/material.dart';

import 'platform_pdf_view_stub.dart'
    if (dart.library.html) 'platform_pdf_view_web.dart' as impl;

/// Innebygd PDF-visning (iframe på web, lenke på mobil/desktop).
class PlatformPdfView extends StatelessWidget {
  final String url;

  const PlatformPdfView({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return impl.buildPlatformPdfView(url);
  }
}
