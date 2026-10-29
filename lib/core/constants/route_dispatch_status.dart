import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/partner/partner_links.dart';

/// Visuell status for rute-fordeling — tre tydelige farger:
/// oransje = kladd, rød = venter på aksept, grønn = akseptert.
abstract final class RouteDispatchStatus {
  static const staged = 'staged';
  static const registered = 'registered';
  static const sent = 'sent';

  // Soft, saturated status hues — readable as full cell fills.
  static const colorDraft = Color(0xFFE8913A);
  static const colorWaiting = Color(0xFFE05252);
  static const colorAccepted = Color(0xFF3BA55C);
  static const colorRejected = Color(0xFF9B59B6);
  static const colorNeutral = Color(0xFF7B8A96);

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

  /// Kort, lesbar tittel — uten UUID/filnavn-søppel.
  static String cleanTitle(PartnerRouteShare share) {
    final raw = (share.title ?? '').trim();
    if (raw.isEmpty) return 'Rute';
    final unitPdf = RegExp(
      r'^([A-Za-z0-9_]+)\s*[—–-]\s*.+\.pdf$',
      caseSensitive: false,
    ).firstMatch(raw);
    if (unitPdf != null) return unitPdf.group(1)!;
    if (raw.toLowerCase().endsWith('.pdf') && raw.length > 28) {
      return 'PDF-rute';
    }
    final head = raw.split(RegExp(r'[—–]')).first.trim();
    return head.isEmpty ? 'Rute' : head;
  }

  static String? _metaLine(String notes, RegExp pattern) {
    final m = pattern.firstMatch(notes);
    if (m == null) return null;
    final v = (m.group(1) ?? '').trim();
    return v.isEmpty ? null : v;
  }

  /// Nyttige felt fra auto-notater (uten rå PDF-linjer).
  static ({String? area, String? stowing, String? freeNote}) parseUsefulNotes(
    String? notes,
  ) {
    final raw = (notes ?? '').trim();
    if (raw.isEmpty) {
      return (area: null, stowing: null, freeNote: null);
    }
    final area = _metaLine(
      raw,
      RegExp(r'Omr[aå]de:\s*([^\n]+)', caseSensitive: false),
    );
    final stowing = _metaLine(
      raw,
      RegExp(
        r'(?:Stowing\s*Lane|Stowing):\s*([^\n]+)',
        caseSensitive: false,
      ),
    );
    final free = raw
        .split('\n')
        .map((l) => l.trim())
        .where(
          (l) =>
              l.isNotEmpty &&
              !RegExp(
                r'^(Rutedato\s*\(PDF\)|Omr[aå]de|Skift\s*\(auto\)|Sjåfør\s*\(PDF\)|Stowing)',
                caseSensitive: false,
              ).hasMatch(l),
        )
        .join(' · ');
    return (
      area: area?.replaceAll(RegExp(r'\s*\(gjetning\)\s*', caseSensitive: false), '').trim(),
      stowing: stowing,
      freeNote: free.isEmpty ? null : free,
    );
  }

  static String tooltipForShare(PartnerRouteShare share, {String? shiftName}) {
    final meta = parseUsefulNotes(share.notes);
    final day = (share.routeStartAt ?? share.shareDate).toLocal();
    final start = share.routeStartAt != null
        ? DateFormat('HH:mm', 'nb').format(share.routeStartAt!.toLocal())
        : null;

    final buf = <String>[
      simpleLabelForShare(share),
      cleanTitle(share),
      [
        DateFormat('EEE d. MMM', 'nb').format(day),
        if (start != null) 'kl. $start',
      ].join(' · '),
    ];

    if (shiftName?.trim().isNotEmpty == true) {
      buf.add('Skift: ${shiftName!.trim()}');
    }
    if (meta.area != null) buf.add('Område: ${meta.area}');
    if (meta.stowing != null) buf.add('Stowing: ${meta.stowing}');

    if (share.isSentWithNotify) {
      final channels = share.notifyChannels
          .map((c) => switch (c) {
                'app' => 'Push',
                'sms' => 'SMS',
                'email' => 'E-post',
                _ => c,
              })
          .where((c) => c.isNotEmpty)
          .join('+');
      final pdf = share.pdfWasOpened ? 'PDF åpnet' : 'PDF ikke åpnet';
      buf.add(
        [
          if (channels.isNotEmpty) 'Varslet $channels',
          pdf,
        ].join(' · '),
      );
    } else if (share.isStaged) {
      buf.add('Kladd — ikke varslet');
    }

    if (share.ackStatus == 'accepted' && share.ackAt != null) {
      buf.add('Akseptert ${_timeFmt.format(share.ackAt!.toLocal())}');
    } else if (share.ackStatus == 'rejected') {
      buf.add('Avvist');
    }

    if (meta.freeNote != null) buf.add(meta.freeNote!);

    return buf.join('\n');
  }
}
