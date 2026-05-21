import 'package:flutter/material.dart';

import '../../../core/services/partner/partner_service.dart';
import 'partner_route_auto_mass_sheet.dart';

/// SAP-ruter åpner samme popup som AUTO MASS (auto-fordeling + publisering).
class PartnerSapRoutesSheet {
  PartnerSapRoutesSheet._();

  static Future<bool?> show(
    BuildContext context, {
    required List<FleetPartnerVehicleRow> fleet,
    DateTime? routeDate,
  }) {
    return PartnerRouteMassDispatchSheet.show(
      context,
      fleet: fleet,
      routeDate: routeDate,
      source: PartnerRouteMassSource.sap,
    );
  }
}
