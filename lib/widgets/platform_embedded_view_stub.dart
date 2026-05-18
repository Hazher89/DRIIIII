import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_theme.dart';
import 'platform_office_view.dart';
import 'platform_pdf_view.dart';

Widget buildPlatformEmbeddedView(String url, {String? mimeHint}) {
  final hint = mimeHint?.toLowerCase() ?? '';
  if (hint.contains('pdf')) {
    return PlatformPdfView(url: url);
  }
  if (hint.startsWith('image/')) {
    return Center(child: InteractiveViewer(child: Image.network(url)));
  }
  if (hint.contains('officedocument') || hint.contains('msword')) {
    return PlatformOfficeView(url: url);
  }
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.open_in_browser, size: 64, color: Colors.grey),
        const SizedBox(height: 16),
        const Text('Innebygd forhåndsvisning er best på web.'),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => launchUrl(Uri.parse(url)),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Åpne fil'),
          style: ElevatedButton.styleFrom(
            backgroundColor: DriftProTheme.primaryGreen,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    ),
  );
}
