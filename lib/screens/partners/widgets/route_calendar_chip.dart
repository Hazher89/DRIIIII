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
    final title = compact
        ? label
        : (share.title?.split('—').first.trim().isNotEmpty == true
            ? share.title!.split('—').first.trim()
            : label);

    // Soft fill that still reads clearly as status (not a thin pill).
    final fillTop = Color.lerp(status, Colors.white, isDark ? 0.18 : 0.42)!;
    final fillBottom = Color.lerp(status, Colors.white, isDark ? 0.08 : 0.22)!;
    final onFill = isDark
        ? Colors.white
        : Color.lerp(status, const Color(0xFF0F172A), 0.72)!;

    final chip = Container(
      width: double.infinity,
      height: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [fillTop, fillBottom],
        ),
        border: Border.all(
          color: status.withValues(alpha: isDark ? 0.55 : 0.35),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: compact ? 7 : 8,
                height: compact ? 7 : 8,
                decoration: BoxDecoration(
                  color: status,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  start,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: compact ? 11 : 12,
                    color: onFill,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
              height: 1.15,
              color: onFill.withValues(alpha: 0.88),
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
