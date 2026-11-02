import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/mavi_fleet_roles.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../models/partner/partner_links.dart';

/// Ledige MAVI-biler — én kompakt rad med tall + utvidbare koder.
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
          final sd =
              DateTime(s.shareDate.year, s.shareDate.month, s.shareDate.day);
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
  State<PartnerAvailableVehiclesPanel> createState() =>
      _PartnerAvailableVehiclesPanelState();
}

class _PartnerAvailableVehiclesPanelState
    extends State<PartnerAvailableVehiclesPanel> {
  String? _expandedRole;

  Map<String, List<FleetPartnerVehicleRow>> _groupByRole(
    List<FleetPartnerVehicleRow> available,
  ) {
    final map = {
      for (final r in MaviFleetRoles.all) r: <FleetPartnerVehicleRow>[],
    };
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
    final expanded = _expandedRole;
    final expandedList =
        expanded == null ? const <FleetPartnerVehicleRow>[] : (byRole[expanded] ?? []);
    final accent = expanded == null
        ? const Color(0xFF0D9488)
        : PartnerAvailableVehiclesPanel.roleColor(expanded);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
              const Text(
                'Ledige',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${available.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: Color(0xFF0D9488),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                dayLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280),
                ),
              ),
              const Spacer(),
              Text(
                expanded == null ? 'Trykk type for koder' : 'Skjul koder',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: MaviFleetRoles.all.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final role = MaviFleetRoles.all[i];
                final n = byRole[role]!.length;
                final selected = _expandedRole == role;
                final color = PartnerAvailableVehiclesPanel.roleColor(role);
                return Material(
                  color: selected ? color : color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() {
                      _expandedRole = selected ? null : role;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$n',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: selected ? Colors.white : color,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            MaviFleetRoles.label(role),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: selected ? Colors.white : color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (expanded != null) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 72),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withValues(alpha: 0.22)),
              ),
              child: expandedList.isEmpty
                  ? Center(
                      child: Text(
                        'Ingen ledige ${MaviFleetRoles.label(expanded)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: expandedList.map((row) {
                          final mavi =
                              MaviUnitCodes.normalize(row.vehicle.unitCode);
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              mavi,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                color: accent,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

typedef PartnerAvailableVehiclesBar = PartnerAvailableVehiclesPanel;
