import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/config/driftpro_client.dart';
import '../../../core/constants/mavi_fleet_roles.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../models/partner/partner_links.dart';

/// Ledige MAVI-biler — kompakt status per biltype (hvit / nøytral stil).
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

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'FLÅTE · LEDIGE I DAG',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.5,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
              Text(
                '$dayLabel · ${available.length} ledige',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
          if (untyped > 0)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Noen biler mangler biltype (sett under Bedrifter)',
                style: TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
              ),
            ),
          const SizedBox(height: 10),
          DriftProClient.isMobile
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(MaviFleetRoles.all.length, (i) {
                      final r = MaviFleetRoles.all[i];
                      final n = byRole[r]!.length;
                      final selected = _roleIndex == i;
                      return Padding(
                        padding: EdgeInsets.only(right: i == MaviFleetRoles.all.length - 1 ? 0 : 8),
                        child: _roleFilterChip(
                          role: r,
                          count: n,
                          selected: selected,
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
                    final selected = _roleIndex == i;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                        child: _roleFilterChip(
                          role: r,
                          count: n,
                          selected: selected,
                          onTap: () => setState(() => _roleIndex = i),
                        ),
                      ),
                    );
                  }),
                ),
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(maxHeight: 88),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: list.isEmpty
                ? Center(
                    child: Text(
                      'Ingen ledige ${MaviFleetRoles.label(role)}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                    ),
                  )
                : SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: list.map((row) {
                        final mavi = MaviUnitCodes.normalize(row.vehicle.unitCode);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Text(
                            mavi,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: Color(0xFF111827),
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: DriftProClient.isMobile ? 10 : 8,
            horizontal: DriftProClient.isMobile ? 14 : 4,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? const Color(0xFF111827) : const Color(0xFFE5E7EB),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: selected ? const Color(0xFF111827) : const Color(0xFF6B7280),
                ),
              ),
              Text(
                MaviFleetRoles.label(role),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: DriftProClient.isMobile ? 11 : 9,
                  fontWeight: FontWeight.w600,
                  color: selected ? const Color(0xFF111827) : const Color(0xFF6B7280),
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
