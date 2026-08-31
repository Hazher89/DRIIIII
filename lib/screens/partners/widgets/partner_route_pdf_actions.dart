import 'dart:async';
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
import '../owner_portal/owner_portal_route_actions.dart';

typedef PartnerRouteReloadCallback = Future<void> Function();

/// Delte PDF-handlinger for ruteplanlegging og sjåførportal.
class PartnerRoutePdfActions {
  PartnerRoutePdfActions._();

  static Future<void> openPdf(BuildContext context, PartnerRouteShare share) async {
    await _openPdfInternal(context, share: share);
  }

  /// Partner: les PDF og aksepter i samme flyt (enklest for sjåfør/eier).
  /// Returnerer true hvis ruten ble akseptert i denne flyten.
  static Future<bool> openPdfWithAcceptFlow(
    BuildContext context, {
    required PartnerRouteShare share,
    bool onBehalfOfDriver = false,
    PartnerRouteReloadCallback? onReload,
  }) async {
    return _openPdfInternal(
      context,
      share: share,
      acceptFlow: share.requiresAck,
      onBehalfOfDriver: onBehalfOfDriver,
      onReload: onReload,
    );
  }

  static Future<bool> _openPdfInternal(
    BuildContext context, {
    required PartnerRouteShare share,
    bool acceptFlow = false,
    bool onBehalfOfDriver = false,
    PartnerRouteReloadCallback? onReload,
  }) async {
    final path = share.pdfStoragePath.trim();
    if (path.isEmpty) {
      _snack(context, 'PDF mangler for denne ruten.', isError: true);
      return false;
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
      if (!context.mounted) return false;
      if (bytes != null && bytes.isNotEmpty) {
        unawaited(PartnerService.markRoutePdfOpened(share.id));
        return await _showPdfBytesViewer(
          context,
          bytes: bytes,
          title: title,
          share: acceptFlow ? share : null,
          onBehalfOfDriver: onBehalfOfDriver,
          onReload: onReload,
        );
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
    return false;
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

  static Future<bool> _showPdfBytesViewer(
    BuildContext context, {
    required Uint8List bytes,
    required String title,
    PartnerRouteShare? share,
    bool onBehalfOfDriver = false,
    PartnerRouteReloadCallback? onReload,
  }) async {
    var accepted = false;
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
          bottomNavigationBar: share != null && share.requiresAck
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Etter at du har lest ruten — trykk aksepter',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 54,
                          child: FilledButton.icon(
                            onPressed: () async {
                              final ok = await ownerPortalSetRouteAck(
                                ctx,
                                share,
                                accepted: true,
                                onDone: onReload ?? () async {},
                                onBehalfOfDriver: onBehalfOfDriver,
                              );
                              if (ok && ctx.mounted) {
                                accepted = true;
                                Navigator.pop(ctx);
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                            ),
                            icon: const Icon(Icons.check_circle, size: 26),
                            label: const Text(
                              'Aksepter rute',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
    return accepted;
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

  static Color ackDotColor(PartnerRouteShare share) =>
      RouteDispatchStatus.cellColorForShare(share);

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
