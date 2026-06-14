import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'partner_route_pdf_bytes_url_stub.dart'
    if (dart.library.io) 'partner_route_pdf_bytes_url_io.dart'
    if (dart.library.html) 'partner_route_pdf_bytes_url_web.dart' as pdf_bytes_url;

import '../../../core/services/partner/partner_service.dart';
import '../../../core/utils/open_external_url.dart';
import '../../../core/constants/route_dispatch_status.dart';
import '../../../models/partner/partner_links.dart';
import '../../../widgets/platform_pdf_bytes_view.dart';

/// Delte PDF-handlinger for ruteplanlegging og sjåførportal.
class PartnerRoutePdfActions {
  PartnerRoutePdfActions._();

  static Future<void> openPdf(BuildContext context, PartnerRouteShare share) async {
    final path = share.pdfStoragePath.trim();
    if (path.isEmpty) {
      _snack(context, 'PDF mangler for denne ruten.', isError: true);
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
            Text('Henter PDF…'),
          ],
        ),
        duration: Duration(seconds: 45),
      ),
    );

    final title = share.title ?? 'Rute-PDF';
    try {
      // Nedlasting først — fungerer for bedriftsansvarlig/sjåfør (Dropbox + Supabase).
      final bytes = await PartnerService.downloadRoutePdfBytes(path);
      messenger?.hideCurrentSnackBar();
      if (!context.mounted) return;
      if (bytes != null && bytes.isNotEmpty) {
        await openPdfBytes(context, bytes: bytes, title: title);
        return;
      }

      if (context.mounted) {
        _snack(
          context,
          'Kunne ikke hente PDF fra lagring. Sjekk at skylagring er koblet '
          'eller at Storage-bucket «documents» finnes i Supabase.',
          isError: true,
        );
      }
    } catch (e) {
      messenger?.hideCurrentSnackBar();
      if (context.mounted) {
        _snack(context, 'Kunne ikke åpne PDF: $e', isError: true);
      }
    }
  }

  static Future<void> openPdfBytes(
    BuildContext context, {
    required Uint8List bytes,
    required String title,
  }) async {
    if (bytes.isEmpty) {
      _snack(context, 'PDF er tom.', isError: true);
      return;
    }
    try {
      if (!context.mounted) return;
      await _showPdfBytesViewer(context, bytes: bytes, title: title);
    } catch (e) {
      if (context.mounted) {
        _snack(context, 'Kunne ikke vise PDF: $e', isError: true);
      }
    }
  }

  static Future<void> _showPdfBytesViewer(
    BuildContext context, {
    required Uint8List bytes,
    required String title,
  }) async {
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
                onPressed: () async {
                  final url = await pdf_bytes_url.pdfBytesToViewUrl(bytes);
                  if (url != null && url.isNotEmpty) {
                    await openExternalUrl(url);
                  }
                },
              ),
              IconButton(
                tooltip: 'Lukk',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          body: PlatformPdfBytesView(
            bytes: bytes,
            fileName: title.endsWith('.pdf') ? title : '$title.pdf',
          ),
        ),
      ),
    );
  }

  static void _snack(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  static Color ackDotColor(PartnerRouteShare share) {
    if (share.isStaged) return RouteDispatchStatus.cellColor(RouteDispatchStatus.staged);
    if (share.isRegistered) return RouteDispatchStatus.cellColor(RouteDispatchStatus.registered);
    if (share.ackStatus == 'accepted') return RouteDispatchStatus.cellColor(RouteDispatchStatus.sent);
    return Colors.red;
  }

  static Widget ackDot(PartnerRouteShare share, {double size = 10}) {
    final color = ackDotColor(share);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 3)],
      ),
    );
  }
}
