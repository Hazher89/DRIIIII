import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Widget buildPlatformOfficeView(String url) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.description_outlined, size: 64, color: Colors.grey),
        const SizedBox(height: 12),
        const Text('Office-forhåndsvisning krever web-versjonen.'),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => launchUrl(Uri.parse(url)),
          icon: const Icon(Icons.download),
          label: const Text('Last ned / åpne'),
        ),
      ],
    ),
  );
}
