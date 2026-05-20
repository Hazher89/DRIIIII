import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/fleet_analytics_service.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/vehicle_inspection.dart';
import '../widgets/partner_ui.dart';

DateTime ownerRouteCalendarDay(PartnerRouteShare r) {
  final t = r.routeStartAt ?? r.shareDate;
  return DateTime(t.year, t.month, t.day);
}

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

bool ownerRouteIsToday(PartnerRouteShare r) {
  final day = ownerRouteCalendarDay(r);
  final t = _startOfDay(DateTime.now());
  return day == t;
}

bool ownerRouteIsFuture(PartnerRouteShare r) {
  return ownerRouteCalendarDay(r).isAfter(_startOfDay(DateTime.now()));
}

bool ownerRouteIsPast(PartnerRouteShare r) {
  return ownerRouteCalendarDay(r).isBefore(_startOfDay(DateTime.now()));
}

bool ownerRouteIsActive(PartnerRouteShare r) {
  if (r.ackStatus == 'pending') return true;
  final now = DateTime.now();
  final startOfToday = _startOfDay(now);
  return !ownerRouteCalendarDay(r).isBefore(startOfToday.subtract(const Duration(days: 1)));
}

class OwnerVehicleStats {
  final PartnerVehicle vehicle;
  final int routeDays;
  final int jobDays;
  final int idleDays;
  final int friDays;
  final int routesToday;
  final int pendingAck;
  final int totalRoutes;

  const OwnerVehicleStats({
    required this.vehicle,
    required this.routeDays,
    required this.jobDays,
    required this.idleDays,
    required this.friDays,
    required this.routesToday,
    required this.pendingAck,
    required this.totalRoutes,
  });

  int get trackedDays => jobDays + idleDays + friDays;

  double get utilizationPercent =>
      trackedDays > 0 ? (jobDays / trackedDays) * 100 : (routeDays > 0 ? 100 : 0);
}

class OwnerPortalData {
  final Partner partner;
  final List<PartnerVehicle> vehicles;
  final List<PartnerRouteShare> routes;
  final List<PartnerVehicleFleetSnapshot> snapshots;
  final List<PartnerDocument> documents;
  final List<PartnerMeeting> meetings;
  final List<PartnerVehicleInspection> inspections;
  final FleetAnalyticsSummary summary90;
  final List<OwnerVehicleStats> vehicleStats;

  List<PartnerRouteShare> get routesToday =>
      routes.where(ownerRouteIsToday).toList();

  List<PartnerRouteShare> get routesUpcoming =>
      routes.where((r) => ownerRouteIsActive(r) && !ownerRouteIsToday(r)).toList();

  List<PartnerRouteShare> get routesPast {
    final past = routes
        .where((r) => ownerRouteIsPast(r) || (!ownerRouteIsActive(r) && !ownerRouteIsFuture(r)))
        .toList();
    past.sort((a, b) => ownerRouteCalendarDay(b).compareTo(ownerRouteCalendarDay(a)));
    return past;
  }

  int get pendingAckTotal => routes.where((r) => r.ackStatus == 'pending').length;

  final Map<String, FleetShiftDefinition> shiftsById;

  const OwnerPortalData({
    required this.partner,
    required this.vehicles,
    required this.routes,
    required this.snapshots,
    required this.documents,
    required this.meetings,
    required this.inspections,
    required this.summary90,
    required this.vehicleStats,
    required this.shiftsById,
  });

  static Future<OwnerPortalData> load(Partner partner) async {
    final vehicles = await PartnerService.fetchVehicles(partner.id);
    final vidSet = vehicles.map((v) => v.id).toSet();
    final routes = await PartnerService.fetchRouteShares(partner.id, sentOnly: true);
    final now = DateTime.now();
    final snapshots = await PartnerService.fetchFleetSnapshotsRange(
      companyId: partner.companyId,
      from: now.subtract(const Duration(days: 90)),
      to: now,
    );
    final partnerSnaps = snapshots.where((s) => vidSet.contains(s.partnerVehicleId)).toList();
    final docs = await PartnerService.fetchOwnerPortalDocuments(partner.id);
    final meetings = await PartnerService.fetchPortalMeetings(partner.id);
    final inspections = await PartnerService.fetchVehicleInspections(partner.id);
    final shiftList = await PartnerService.fetchFleetShifts(partner.companyId);
    final shiftsById = {for (final s in shiftList) s.id: s};

    final labels = {for (final v in vehicles) v.id: MaviUnitCodes.normalize(v.unitCode)};
    final v2p = {for (final v in vehicles) v.id: partner.id};
    final summary = FleetAnalyticsService.build(
      period: FleetStatsPeriod.days90,
      shares: routes,
      snapshots: partnerSnaps,
      vehicleLabels: labels,
      partnerNames: {partner.id: partner.name},
      vehicleToPartnerId: v2p,
      vehiclesPerPartner: {partner.id: vehicles.length},
    );

    final stats = <OwnerVehicleStats>[];
    for (final v in vehicles) {
      final vid = v.id;
      final vRoutes = routes.where((r) => r.partnerVehicleId == vid).toList();
      final vSnaps = partnerSnaps.where((s) => s.partnerVehicleId == vid);
      final routeDayKeys = vRoutes.map((r) => ownerRouteCalendarDay(r).millisecondsSinceEpoch).toSet();
      var har = 0, ledig = 0, fri = 0;
      for (final s in vSnaps) {
        switch (s.status) {
          case 'har_rute':
            har++;
            break;
          case 'ledig':
            ledig++;
            break;
          case 'fri':
            fri++;
            break;
        }
      }
      stats.add(
        OwnerVehicleStats(
          vehicle: v,
          routeDays: routeDayKeys.length,
          jobDays: har,
          idleDays: ledig,
          friDays: fri,
          routesToday: vRoutes.where(ownerRouteIsToday).length,
          pendingAck: vRoutes.where((r) => r.ackStatus == 'pending').length,
          totalRoutes: vRoutes.length,
        ),
      );
    }
    stats.sort((a, b) => b.utilizationPercent.compareTo(a.utilizationPercent));

    return OwnerPortalData(
      partner: partner,
      vehicles: vehicles,
      routes: routes,
      snapshots: partnerSnaps,
      documents: docs,
      meetings: meetings.where((m) => !m.isArchived).toList(),
      inspections: inspections,
      summary90: summary,
      vehicleStats: stats,
      shiftsById: shiftsById,
    );
  }
}

String portalShiftTypeLabel(FleetShiftDefinition? shift) {
  if (shift == null) return '—';
  if (shift.isAvailability) return 'Tilgjengelighet';
  return shift.shiftKind == 'route_ops' ? 'Rutedrift' : shift.shiftKind;
}

String ownerRouteArea(PartnerRouteShare route, Map<String, FleetShiftDefinition> shifts) {
  final sid = route.shiftId;
  if (sid != null) {
    final shift = shifts[sid];
    final rg = shift?.regionGroup?.trim();
    if (rg != null && rg.isNotEmpty) return rg;
    final name = shift?.name.trim();
    if (name != null && name.isNotEmpty) return name;
  }
  final title = route.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  return '—';
}

class OwnerSectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const OwnerSectionTitle({super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                if (subtitle != null)
                  Text(subtitle!, style: TextStyle(fontSize: 12, color: PartnerUi.mutedText(context))),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class OwnerKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accent;

  const OwnerKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final c = accent ?? DriftProTheme.primaryGreen;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
        boxShadow: isDark ? null : DriftProTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c, size: 22),
          const SizedBox(height: 10),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: PartnerUi.mutedText(context))),
        ],
      ),
    );
  }
}

class OwnerVehicleStackCard extends StatelessWidget {
  final OwnerVehicleStats stats;
  final VoidCallback? onTap;

  const OwnerVehicleStackCard({super.key, required this.stats, this.onTap});

  @override
  Widget build(BuildContext context) {
    final v = stats.vehicle;
    final unit = MaviUnitCodes.normalize(v.unitCode);
    final util = stats.utilizationPercent.clamp(0, 100);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      unit,
                      style: const TextStyle(fontWeight: FontWeight.w900, color: DriftProTheme.primaryGreen),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          v.registrationNumber,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                        if (v.driverName != null && v.driverName!.trim().isNotEmpty)
                          Text(v.driverName!, style: TextStyle(fontSize: 12, color: PartnerUi.mutedText(context))),
                      ],
                    ),
                  ),
                  Text(
                    '${util.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: util >= 60 ? DriftProTheme.primaryGreen : Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: util / 100,
                  minHeight: 8,
                  backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                  color: util >= 60 ? DriftProTheme.primaryGreen : Colors.orange,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Jobb ${stats.jobDays} d · Ledig ${stats.idleDays} d · Fri ${stats.friDays} d'
                '${stats.pendingAck > 0 ? ' · ${stats.pendingAck} venter' : ''}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PartnerUi.mutedText(context)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

}

String ownerFmtDate(DateTime d) => DateFormat('d. MMM yyyy', 'nb').format(d.toLocal());
String ownerFmtDateTime(DateTime d) => DateFormat('d. MMM yyyy HH:mm', 'nb').format(d.toLocal());
