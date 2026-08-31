import 'package:flutter/material.dart';

import '../../core/services/notification/push_navigation_target.dart';
import '../../core/services/partner/partner_deduction_service.dart';
import '../../core/services/partner/partner_service.dart';
import '../../models/partner/partner.dart';
import '../../models/partner/partner_deduction_case.dart';
import 'owner_portal/owner_portal_common.dart';
import 'owner_portal/owner_portal_deduction_detail_sheet.dart';
import 'owner_portal/owner_portal_timesheet_page.dart';
import 'widgets/partner_portal_route_detail_page.dart';
import 'widgets/partner_route_pdf_actions.dart';
import 'widgets/vehicle_inspection_detail_page.dart';

/// Åpner riktig partner-skjerm etter push-varsel.
abstract final class PartnerPushNavigation {
  static Future<void> open(
    BuildContext context, {
    required PushNavigationTarget target,
    required Partner partner,
    required String? portalAccountKind,
  }) async {
    switch (target.kind) {
      case PushNavKind.partnerRoute:
        final id = target.id;
        if (id != null) {
          await _openRoute(
            context,
            partner: partner,
            routeShareId: id,
            isOwner: portalAccountKind == 'owner',
          );
        }
      case PushNavKind.partnerDeduction:
        final id = target.id;
        if (id != null) await _openDeduction(context, partner: partner, caseId: id);
      case PushNavKind.partnerInspection:
        final id = target.id;
        if (id != null) {
          await _openInspection(
            context,
            partner: partner,
            inspectionId: id,
            isOwner: portalAccountKind == 'owner',
          );
        }
      case PushNavKind.partnerTimesheet:
        if (!context.mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => OwnerPortalTimesheetPage(partner: partner),
          ),
        );
      default:
        break;
    }
  }

  static Future<void> _openRoute(
    BuildContext context, {
    required Partner partner,
    required String routeShareId,
    required bool isOwner,
  }) async {
    final share = await PartnerService.fetchRouteShareById(routeShareId);
    if (share == null || !context.mounted) return;
    final data = await OwnerPortalData.load(partner);
    if (!context.mounted) return;
    if (share.requiresAck) {
      await PartnerRoutePdfActions.openPdfWithAcceptFlow(
        context,
        share: share,
        onBehalfOfDriver: isOwner,
        onReload: () async {},
      );
      return;
    }
    await PartnerPortalRouteDetailPage.open(
      context,
      route: share,
      shifts: data.shiftsById,
      onReload: () async {},
      onBehalfOfDriver: isOwner,
    );
  }

  static Future<void> _openDeduction(
    BuildContext context, {
    required Partner partner,
    required String caseId,
  }) async {
    final cases = await PartnerDeductionService.listCasesPortal(partnerId: partner.id);
    PartnerDeductionCase? row;
    for (final c in cases) {
      if (c.id == caseId) {
        row = c;
        break;
      }
    }
    if (row == null || !context.mounted) return;
    await OwnerPortalDeductionDetailSheet.show(context, row);
  }

  static Future<void> _openInspection(
    BuildContext context, {
    required Partner partner,
    required String inspectionId,
    required bool isOwner,
  }) async {
    final inspection = await PartnerService.fetchVehicleInspectionById(inspectionId);
    if (inspection == null || !context.mounted) return;
    await VehicleInspectionDetailPage.open(
      context,
      inspection: inspection,
      partner: partner,
      canCloseFollowUp: isOwner,
    );
  }
}
