import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/route_dispatch_status.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';

/// Kalender-rute med farge etter lese/aksept-status og hover-tooltip (web/desktop).
class RouteCalendarChip extends StatelessWidget {
  const RouteCalendarChip({
    super.key,
    required this.share,
    required this.day,
    required this.isDark,
    required this.shiftColor,
    this.shiftName,
    this.compact = false,
  });

  final PartnerRouteShare share;
  final DateTime day;
  final bool isDark;
  final Color shiftColor;
  final String? shiftName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final start = TimeOfDay.fromDateTime(
      share.routeStartAt?.toLocal() ?? DateTime(day.year, day.month, day.day, 6),
    ).format(context);

    final chip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 10,
        vertical: compact ? 5 : 8,
      ),
      decoration: BoxDecoration(
        color: RouteDispatchStatus.cellFillForShare(share, isDark: isDark),
        borderRadius: BorderRadius.circular(compact ? 6 : 10),
        border: Border(left: BorderSide(color: shiftColor, width: compact ? 4 : 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _statusDot(),
              SizedBox(width: compact ? 4 : 6),
              if (compact)
                Expanded(
                  child: Text(
                    start,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10),
                  ),
                )
              else
                Text(start, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              if (!compact) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    share.title?.split('—').first ?? 'Rute',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
          if (compact)
            Text(
              share.title?.split('—').first ?? 'Rute',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9, height: 1.15),
            ),
        ],
      ),
    );

    return Tooltip(
      message: RouteDispatchStatus.tooltipForShare(share, shiftName: shiftName),
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 350),
      child: chip,
    );
  }

  Widget _statusDot() {
    final color = RouteDispatchStatus.cellColorForShare(share);
    final size = compact ? 8.0 : 9.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1),
      ),
    );
  }
}

String? shiftNameFor(List<FleetShiftDefinition> shifts, String? shiftId) {
  if (shiftId == null) return null;
  for (final s in shifts) {
    if (s.id == shiftId) return s.name;
  }
  return null;
}

String formatRouteDayHeader(DateTime day) =>
    DateFormat.yMMMMEEEEd('nb_NO').format(day);
