import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_theme.dart';

Widget buildPlatformPdfView(String url) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.picture_as_pdf, size: 72, color: Colors.grey),
        const SizedBox(height: 16),
        const Text('Åpne PDF i nettleser for visning.'),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () => launchUrl(Uri.parse(url)),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Åpne PDF'),
          style: ElevatedButton.styleFrom(
            backgroundColor: DriftProTheme.primaryGreen,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    ),
  );
}
