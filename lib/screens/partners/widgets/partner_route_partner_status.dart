import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/partner/partner_links.dart';
import '../../../models/partner/partner_route_dispatch_history.dart';

/// MAVI: viser om partner har lest PDF og akseptert ruten.
class PartnerRoutePartnerStatus extends StatelessWidget {
  const PartnerRoutePartnerStatus({
    super.key,
    required PartnerRouteShare share,
    this.compact = false,
  })  : _share = share,
        _history = null,
        pdfOpenedByName = null,
        ackByName = null;

  PartnerRoutePartnerStatus.fromHistory({
    super.key,
    required PartnerRouteDispatchHistoryRow row,
    this.compact = false,
  })  : _share = null,
        _history = row,
        pdfOpenedByName = row.pdfOpenedByName,
        ackByName = row.ackByName;

  final PartnerRouteShare? _share;
  final PartnerRouteDispatchHistoryRow? _history;
  final bool compact;
  final String? pdfOpenedByName;
  final String? ackByName;

  static final _timeFmt = DateFormat('dd.MM.yyyy HH:mm', 'nb');

  String _fmt(DateTime? t) => t == null ? '—' : _timeFmt.format(t.toLocal());

  @override
  Widget build(BuildContext context) {
    final share = _share;
    final history = _history;

    if (share != null && !share.isSentWithNotify && !share.isRegistered) {
      return const SizedBox.shrink();
    }
    if (history != null && history.dispatchStatus == 'staged') {
      return const SizedBox.shrink();
    }

    final sent = share?.isSentWithNotify == true || history?.dispatchStatus == 'sent';
    final pdfAt = history?.pdfOpenedAt ?? share?.pdfOpenedAt;
    final pdfName = pdfOpenedByName;
    final pdfCount = history?.pdfOpenCount ?? share?.pdfOpenCount ?? 0;
    final ackStatus = history?.ackStatus ?? share?.ackStatus;
    final ackAt = history?.ackAt ?? share?.ackAt;
    final ackName = ackByName;
    final needsAck = share?.requiresAck ??
        (ackStatus != null &&
            ackStatus != 'not_required' &&
            history?.dispatchStatus != 'registered');

    if (!sent && history?.wasNotified != true) {
      return const SizedBox.shrink();
    }

    if (compact) {
      return Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          _Chip(
            icon: pdfAt != null ? Icons.menu_book_rounded : Icons.menu_book_outlined,
            label: pdfAt != null ? 'PDF lest' : 'PDF ulest',
            color: pdfAt != null ? Colors.teal : Colors.orange.shade800,
          ),
          if (needsAck)
            _Chip(
              icon: ackStatus == 'accepted'
                  ? Icons.check_circle
                  : ackStatus == 'rejected'
                      ? Icons.cancel
                      : Icons.hourglass_top,
              label: _ackShort(ackStatus),
              color: ackStatus == 'accepted'
                  ? Colors.green.shade700
                  : ackStatus == 'rejected'
                      ? Colors.red.shade700
                      : Colors.orange.shade800,
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Line(
          icon: pdfAt != null ? Icons.menu_book_rounded : Icons.menu_book_outlined,
          title: 'PDF lest av partner',
          value: pdfAt != null
              ? '${_fmt(pdfAt)}${pdfName != null && pdfName.trim().isNotEmpty ? ' · $pdfName' : ''}'
                  '${pdfCount > 1 ? ' ($pdfCount×)' : ''}'
              : 'Ikke åpnet ennå',
          accent: pdfAt != null ? Colors.teal : Colors.orange.shade800,
        ),
        if (needsAck) ...[
          const SizedBox(height: 6),
          _Line(
            icon: ackStatus == 'accepted'
                ? Icons.check_circle_outline
                : ackStatus == 'rejected'
                    ? Icons.cancel_outlined
                    : Icons.pending_actions_outlined,
            title: 'Aksept',
            value: ackAt != null
                ? '${_ackLabel(ackStatus)} · ${_fmt(ackAt)}'
                    '${ackName != null && ackName.trim().isNotEmpty ? ' · $ackName' : ''}'
                : _ackLabel(ackStatus),
            accent: ackStatus == 'accepted'
                ? Colors.green.shade700
                : ackStatus == 'rejected'
                    ? Colors.red.shade700
                    : Colors.orange.shade800,
          ),
        ],
      ],
    );
  }

  static String _ackShort(String? status) => switch (status) {
        'accepted' => 'Akseptert',
        'rejected' => 'Avvist',
        'not_required' => 'Ikke påkrevd',
        _ => 'Venter',
      };

  static String _ackLabel(String? status) => switch (status) {
        'accepted' => 'Akseptert',
        'rejected' => 'Avvist',
        'not_required' => 'Ikke påkrevd',
        'pending' => 'Venter på aksept',
        _ => status ?? '—',
      };
}

class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.title,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: accent),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent),
              ),
              Text(value, style: const TextStyle(fontSize: 12.5, height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}
