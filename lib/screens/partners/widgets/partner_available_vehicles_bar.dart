import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/config/driftpro_client.dart';
import '../../../core/constants/mavi_fleet_roles.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../models/partner/partner_links.dart';

/// Ledige MAVI-biler — kompakt status per biltype (fargerik / lys stil).
class PartnerAvailableVehiclesPanel extends StatefulWidget {
  final List<FleetPartnerVehicleRow> fleet;
  final List<PartnerRouteShare> sharesToday;
  final DateTime day;

  const PartnerAvailableVehiclesPanel({
    super.key,
    required this.fleet,
    required this.sharesToday,
    required this.day,
  });

  static List<FleetPartnerVehicleRow> availableToday({
    required List<FleetPartnerVehicleRow> fleet,
    required List<PartnerRouteShare> shares,
    required DateTime day,
  }) {
    final d = DateTime(day.year, day.month, day.day);
    final busy = shares
        .where((s) {
          final sd = DateTime(s.shareDate.year, s.shareDate.month, s.shareDate.day);
          return sd == d && s.partnerVehicleId != null && !s.isStaged;
        })
        .map((s) => s.partnerVehicleId!)
        .toSet();
    return fleet.where((r) => !busy.contains(r.vehicle.id)).toList();
  }

  static Color roleColor(String role) {
    switch (role) {
      case MaviFleetRoles.tjenestebil:
        return const Color(0xFF0D9488);
      case MaviFleetRoles.enmannsbil:
        return const Color(0xFFEA580C);
      case MaviFleetRoles.tomannsbil:
        return const Color(0xFF2563EB);
      case MaviFleetRoles.intern:
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF6B7280);
    }
  }

  @override
  State<PartnerAvailableVehiclesPanel> createState() => _PartnerAvailableVehiclesPanelState();
}

class _PartnerAvailableVehiclesPanelState extends State<PartnerAvailableVehiclesPanel> {
  int _roleIndex = 0;

  Map<String, List<FleetPartnerVehicleRow>> _groupByRole(List<FleetPartnerVehicleRow> available) {
    final map = {for (final r in MaviFleetRoles.all) r: <FleetPartnerVehicleRow>[]};
    for (final row in available) {
      for (final role in MaviFleetRoles.normalize(row.vehicle.fleetRoles)) {
        map[role]!.add(row);
      }
    }
    for (final list in map.values) {
      list.sort((a, b) => a.vehicle.unitCode.compareTo(b.vehicle.unitCode));
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final available = PartnerAvailableVehiclesPanel.availableToday(
      fleet: widget.fleet,
      shares: widget.sharesToday,
      day: widget.day,
    );
    final byRole = _groupByRole(available);
    final dayLabel = DateFormat('d. MMM', 'nb').format(widget.day);
    final role = MaviFleetRoles.all[_roleIndex];
    final list = byRole[role] ?? [];
    final untyped = available.where((r) => MaviFleetRoles.normalize(r.vehicle.fleetRoles).isEmpty).length;
    final accent = PartnerAvailableVehiclesPanel.roleColor(role);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'FLÅTE · LEDIGE I DAG',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 0.4,
                    color: Color(0xFF0D9488),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '$dayLabel · ${available.length} ledige',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
          if (untyped > 0)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Noen biler mangler biltype (sett under Bedrifter)',
                style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
            ),
          const SizedBox(height: 12),
          DriftProClient.isMobile
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(MaviFleetRoles.all.length, (i) {
                      final r = MaviFleetRoles.all[i];
                      final n = byRole[r]!.length;
                      return Padding(
                        padding: EdgeInsets.only(right: i == MaviFleetRoles.all.length - 1 ? 0 : 8),
                        child: _roleFilterChip(
                          role: r,
                          count: n,
                          selected: _roleIndex == i,
                          onTap: () => setState(() => _roleIndex = i),
                        ),
                      );
                    }),
                  ),
                )
              : Row(
                  children: List.generate(MaviFleetRoles.all.length, (i) {
                    final r = MaviFleetRoles.all[i];
                    final n = byRole[r]!.length;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                        child: _roleFilterChip(
                          role: r,
                          count: n,
                          selected: _roleIndex == i,
                          onTap: () => setState(() => _roleIndex = i),
                        ),
                      ),
                    );
                  }),
                ),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 92),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
            ),
            child: list.isEmpty
                ? Center(
                    child: Text(
                      'Ingen ledige ${MaviFleetRoles.label(role)}',
                      style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.w600),
                    ),
                  )
                : SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: list.map((row) {
                        final mavi = MaviUnitCodes.normalize(row.vehicle.unitCode);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: accent.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            mavi,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: accent,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _roleFilterChip({
    required String role,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final color = PartnerAvailableVehiclesPanel.roleColor(role);
    return Material(
      color: selected ? color : color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: DriftProClient.isMobile ? 12 : 10,
            horizontal: DriftProClient.isMobile ? 14 : 6,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : color.withValues(alpha: 0.3),
              width: selected ? 0 : 1.5,
            ),
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: selected ? Colors.white : color,
                ),
              ),
              Text(
                MaviFleetRoles.label(role),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: DriftProClient.isMobile ? 11 : 10,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef PartnerAvailableVehiclesBar = PartnerAvailableVehiclesPanel;
