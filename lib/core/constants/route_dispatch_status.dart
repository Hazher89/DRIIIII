import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/partner/partner_links.dart';

/// Visuell status for rute-fordeling i kalender og lister.
abstract final class RouteDispatchStatus {
  static const staged = 'staged';
  static const registered = 'registered';
  static const sent = 'sent';

  static final _timeFmt = DateFormat('dd.MM.yyyy HH:mm', 'nb');

  static String shortLabel(String status) {
    switch (status) {
      case staged:
        return 'Kladd';
      case registered:
        return 'Uten varsel';
      case sent:
        return 'Varslet';
      default:
        return status;
    }
  }

  static String labelForShare(PartnerRouteShare share) {
    if (share.isStaged) return 'Kladd';
    if (share.isRegistered) return 'Lagt ut uten varsel';
    if (share.ackStatus == 'accepted') return 'Akseptert';
    if (share.ackStatus == 'rejected') return 'Avvist';
    if (share.pdfWasOpened && share.requiresAck) return 'PDF lest — venter aksept';
    if (share.isSentWithNotify) return 'Varslet — PDF ikke lest';
    return shortLabel(share.dispatchStatus);
  }

  static Color cellColorForShare(PartnerRouteShare share) {
    if (share.isStaged) return const Color(0xFFFF9800);
    if (share.isRegistered) return const Color(0xFF78909C);
    if (share.ackStatus == 'accepted') return const Color(0xFF1B5E20);
    if (share.ackStatus == 'rejected') return const Color(0xFFC62828);
    if (share.pdfWasOpened && share.requiresAck) return const Color(0xFF1565C0);
    if (share.isSentWithNotify) return const Color(0xFF2E7D32);
    return const Color(0xFF546E7A);
  }

  /// Bakgrunnsfarge i kalender-rute (legacy dispatch_status).
  static Color cellColor(String status) {
    switch (status) {
      case staged:
        return const Color(0xFFFF9800);
      case registered:
        return const Color(0xFF78909C);
      case sent:
        return const Color(0xFF2E7D32);
      default:
        return const Color(0xFF546E7A);
    }
  }

  static Color cellFillForShare(PartnerRouteShare share, {required bool isDark}) {
    return cellColorForShare(share).withValues(alpha: isDark ? 0.32 : 0.42);
  }

  static Color cellFill(String status, {required bool isDark}) {
    return cellColor(status).withValues(alpha: isDark ? 0.32 : 0.42);
  }

  static bool isVisibleInDriverPortal(String status) => status == sent;

  static String tooltipForShare(PartnerRouteShare share, {String? shiftName}) {
    final buf = <String>[labelForShare(share)];

    if (share.title?.trim().isNotEmpty == true) {
      buf.add(share.title!.trim());
    }

    if (shiftName?.trim().isNotEmpty == true) {
      buf.add('Skift: ${shiftName!.trim()}');
    }

    final day = share.routeStartAt ?? share.shareDate;
    buf.add('Dag: ${DateFormat('EEEE d. MMM yyyy', 'nb').format(day.toLocal())}');

    if (share.routeStartAt != null) {
      buf.add('Start: ${DateFormat('HH:mm', 'nb').format(share.routeStartAt!.toLocal())}');
    }

    if (share.isSentWithNotify && share.notifyChannels.isNotEmpty) {
      final channels = share.notifyChannels
          .map((c) => switch (c) {
                'app' => 'Push',
                'sms' => 'SMS',
                'email' => 'E-post',
                _ => c,
              })
          .join(', ');
      buf.add('Varslet via: $channels');
    }

    if (share.sentAt != null) {
      buf.add('Sendt: ${_timeFmt.format(share.sentAt!.toLocal())}');
    }

    if (share.pdfWasOpened) {
      buf.add('PDF lest: ${_timeFmt.format(share.pdfOpenedAt!.toLocal())}');
      if (share.pdfOpenCount > 1) buf.add('(${share.pdfOpenCount} ganger)');
    } else if (share.isSentWithNotify) {
      buf.add('PDF: ikke åpnet ennå');
    }

    if (share.ackStatus == 'accepted' && share.ackAt != null) {
      buf.add('Akseptert: ${_timeFmt.format(share.ackAt!.toLocal())}');
    } else if (share.ackStatus == 'rejected') {
      buf.add('Avvist${share.ackAt != null ? ' ${_timeFmt.format(share.ackAt!.toLocal())}' : ''}');
    } else if (share.requiresAck) {
      buf.add('Venter på aksept fra sjåfør');
    }

    if ((share.notes ?? '').trim().isNotEmpty) {
      buf.add('Notat: ${share.notes!.trim()}');
    }

    return buf.join('\n');
  }
}
