import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/partner/partner_service.dart';
import '../../../models/partner/partner_links.dart';

/// Delte PDF-handlinger for ruteplanlegging og sjåførportal.
class PartnerRoutePdfActions {
  PartnerRoutePdfActions._();

  static Future<void> openPdf(BuildContext context, PartnerRouteShare share) async {
    try {
      final url = await PartnerService.getRoutePdfSignedUrl(share.pdfStoragePath);
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Kunne ikke åpne lenken');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke åpne PDF: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  static Color ackDotColor(PartnerRouteShare share) {
    if (share.isStaged) return Colors.orange;
    if (share.ackStatus == 'accepted') return Colors.green;
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
