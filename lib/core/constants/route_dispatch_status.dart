import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/partner/partner_links.dart';

/// Visuell status for rute-fordeling — tre tydelige farger:
/// oransje = kladd, rød = venter på aksept, grønn = akseptert.
abstract final class RouteDispatchStatus {
  static const staged = 'staged';
  static const registered = 'registered';
  static const sent = 'sent';

  static const colorDraft = Color(0xFFEF6C00);
  static const colorWaiting = Color(0xFFC62828);
  static const colorAccepted = Color(0xFF2E7D32);
  static const colorRejected = Color(0xFF8E24AA);
  static const colorNeutral = Color(0xFF78909C);

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

  /// Enkel etikett for UI (3 hovedtilstander).
  static String simpleLabelForShare(PartnerRouteShare share) {
    if (share.isStaged) return 'Kladd';
    if (share.ackStatus == 'accepted') return 'Akseptert';
    if (share.ackStatus == 'rejected') return 'Avvist';
    if (share.isRegistered || share.isSentWithNotify || share.requiresAck) {
      return 'Venter på aksept';
    }
    return shortLabel(share.dispatchStatus);
  }

  static String labelForShare(PartnerRouteShare share) {
    if (share.isStaged) return 'Kladd — ikke delt ut';
    if (share.ackStatus == 'accepted') return 'Akseptert';
    if (share.ackStatus == 'rejected') return 'Avvist';
    if (share.pdfWasOpened && share.requiresAck) {
      return 'Venter på aksept (PDF lest)';
    }
    if (share.isSentWithNotify) return 'Venter på aksept';
    if (share.isRegistered) return 'Venter på aksept (uten SMS)';
    return shortLabel(share.dispatchStatus);
  }

  /// Grønn kun ved aksept · oransje kun kladd · rød når utsendt og venter.
  static Color cellColorForShare(PartnerRouteShare share) {
    if (share.isStaged) return colorDraft;
    if (share.ackStatus == 'accepted') return colorAccepted;
    if (share.ackStatus == 'rejected') return colorRejected;
    if (share.isRegistered ||
        share.isSentWithNotify ||
        share.requiresAck ||
        share.pdfWasOpened) {
      return colorWaiting;
    }
    return colorNeutral;
  }

  /// Bakgrunnsfarge i kalender-rute (legacy dispatch_status).
  static Color cellColor(String status) {
    switch (status) {
      case staged:
        return colorDraft;
      case registered:
        return colorWaiting;
      case sent:
        return colorWaiting;
      default:
        return colorNeutral;
    }
  }

  static Color cellFillForShare(PartnerRouteShare share, {required bool isDark}) {
    final c = cellColorForShare(share);
    return c.withValues(alpha: isDark ? 0.28 : 0.22);
  }

  static Color cellFill(String status, {required bool isDark}) {
    return cellColor(status).withValues(alpha: isDark ? 0.28 : 0.22);
  }

  static bool isVisibleInDriverPortal(String status) => status == sent;

  static bool isWaitingAck(PartnerRouteShare share) {
    if (share.isStaged) return false;
    if (share.ackStatus == 'accepted') return false;
    if (share.ackStatus == 'rejected') return true;
    return share.isRegistered || share.isSentWithNotify || share.requiresAck;
  }

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
      buf.add(
        'Avvist${share.ackAt != null ? ' ${_timeFmt.format(share.ackAt!.toLocal())}' : ''}',
      );
    } else if (share.requiresAck) {
      buf.add('Venter på aksept fra sjåfør');
    }

    if ((share.notes ?? '').trim().isNotEmpty) {
      buf.add('Notat: ${share.notes!.trim()}');
    }

    return buf.join('\n');
  }
}
