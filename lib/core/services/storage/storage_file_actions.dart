import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../utils/open_external_url.dart';
import '../../../widgets/platform_pdf_view.dart';
import 'storage_file_access.dart';
import '../../../screens/partners/widgets/partner_route_pdf_bytes_url_stub.dart'
    if (dart.library.io) '../../../screens/partners/widgets/partner_route_pdf_bytes_url_io.dart'
    if (dart.library.html) '../../../screens/partners/widgets/partner_route_pdf_bytes_url_web.dart' as pdf_bytes_url;

/// Åpne lagrede filer (PDF m.m.) med fallback for legacy Supabase-stier.
class StorageFileActions {
  StorageFileActions._();

  static Future<void> open(
    BuildContext context, {
    required String storagePath,
    required String title,
    String? companyId,
  }) async {
    if (storagePath.trim().isEmpty) {
      _snack(context, 'Fil mangler.', isError: true);
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Henter fil…'),
          ],
        ),
        duration: Duration(seconds: 45),
      ),
    );

    try {
      Uint8List? bytes;
      String? url;
      try {
        url = await StorageFileAccess.resolveViewUrl(
          storagePath,
          companyId: companyId,
        );
      } on StorageBytesReady catch (e) {
        bytes = e.bytes;
      }

      messenger?.hideCurrentSnackBar();
      if (!context.mounted) return;

      if (bytes != null) {
        final viewUrl = await pdf_bytes_url.pdfBytesToViewUrl(bytes);
        if (viewUrl == null || viewUrl.isEmpty) {
          _snack(context, 'Forhåndsvisning støttes ikke på denne plattformen.', isError: true);
          return;
        }
        await _showViewer(context, viewUrl, title);
        return;
      }

      if (url != null && url.isNotEmpty) {
        await _showViewer(context, url, title);
      }
    } catch (e) {
      messenger?.hideCurrentSnackBar();
      if (context.mounted) {
        _snack(context, 'Kunne ikke åpne: $e', isError: true);
      }
    }
  }

  static Future<void> _showViewer(
    BuildContext context,
    String url,
    String title,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(title, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: 'Åpne i ny fane',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => openExternalUrl(url),
              ),
              IconButton(
                tooltip: 'Lukk',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          body: PlatformPdfView(url: url),
        ),
      ),
    );
  }

  static void _snack(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 6),
      ),
    );
  }
}
