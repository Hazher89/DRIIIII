import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/config/driftpro_client.dart';
import '../../../core/constants/mavi_fleet_roles.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../models/partner/partner_links.dart';

/// Ledige MAVI-biler — 4 kompakte knapper + MAVI-liste.
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Ledige i dag · $dayLabel',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              const Spacer(),
              Text(
                '${available.length} totalt',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade700),
              ),
            ],
          ),
          if (untyped > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$untyped uten biltype (sett under Bedrifter)',
                style: TextStyle(fontSize: 10, color: Colors.orange.shade800),
              ),
            ),
          const SizedBox(height: 8),
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
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
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
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 88),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: list.isEmpty
                ? Center(
                    child: Text(
                      'Ingen ledige ${MaviFleetRoles.label(role)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF81C784)),
                          ),
                          child: Text(
                            mavi,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
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
      color: selected ? const Color(0xFFE65100) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: DriftProClient.isMobile ? 10 : 8,
            horizontal: DriftProClient.isMobile ? 14 : 4,
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: selected ? Colors.white : const Color(0xFFE65100),
                ),
              ),
              Text(
                MaviFleetRoles.label(role),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: DriftProClient.isMobile ? 11 : 9,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : Colors.grey.shade800,
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
