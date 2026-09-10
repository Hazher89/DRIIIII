import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/route_dispatch_status.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';

/// Kalender-rute med liquid glass og tydelig statusfarge.
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
    final status = RouteDispatchStatus.cellColorForShare(share);
    final label = RouteDispatchStatus.simpleLabelForShare(share);

    final chip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 10,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.14 : 0.72),
            status.withValues(alpha: isDark ? 0.28 : 0.20),
          ],
        ),
        border: Border.all(
          color: status.withValues(alpha: 0.55),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: status.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: compact ? 8 : 9,
                height: compact ? 8 : 9,
                decoration: BoxDecoration(
                  color: status,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: status.withValues(alpha: 0.45),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  start,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: compact ? 10 : 12,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            compact
                ? label
                : (share.title?.split('—').first.trim().isNotEmpty == true
                    ? share.title!.split('—').first.trim()
                    : label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 9 : 11,
              fontWeight: FontWeight.w700,
              height: 1.15,
              color: status.withValues(alpha: 0.95),
            ),
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
}

String? shiftNameFor(List<FleetShiftDefinition> shifts, String? shiftId) {
  if (shiftId == null) return null;
  for (final s in shifts) {
    if (s.id == shiftId) return s.name;
  }
  return null;
}

/// Vis «PDF foreslår …» når valgt skift avviker fra PDF-analyse.
class RoutePdfShiftSuggestionButton extends StatelessWidget {
  const RoutePdfShiftSuggestionButton({
    super.key,
    required this.shifts,
    required this.suggestedShiftId,
    required this.selectedShiftId,
    required this.onApply,
  });

  final List<FleetShiftDefinition> shifts;
  final String? suggestedShiftId;
  final String? selectedShiftId;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final suggested = suggestedShiftId;
    if (suggested == null || suggested.isEmpty || suggested == selectedShiftId) {
      return const SizedBox.shrink();
    }
    final name = shiftNameFor(shifts, suggested) ?? '—';
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onApply,
        icon: const Icon(Icons.auto_fix_high, size: 18),
        label: Text('PDF foreslår: $name'),
      ),
    );
  }
}

String formatRouteDayHeader(DateTime day) =>
    DateFormat.yMMMMEEEEd('nb_NO').format(day);
