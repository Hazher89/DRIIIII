import '../../../core/permissions/user_access.dart';
import '../../../models/partner/partner_links.dart';
import '../supabase_service.dart';
import 'partner_service.dart';

/// Dataminimering i partnerportal: kun egen bedrift (og for sjåfør: egen bil).
class PartnerPortalScope {
  PartnerPortalScope._();

  static Future<void> assertAccess({
    required String partnerId,
    String? partnerVehicleId,
  }) async {
    final me = await SupabaseService.fetchCurrentUserProfile();
    if (me == null) {
      throw StateError('Ikke innlogget.');
    }

    final session = await PartnerService.resolvePortalSession();
    if (session != null) {
      if (session.partnerId != partnerId) {
        throw StateError('Du kan kun se data for din egen samarbeidspartner.');
      }
      if (session.isDriver) {
        final allowedVehicle = session.partnerVehicleId ?? me.partnerVehicleId;
        if (allowedVehicle != null) {
          if (partnerVehicleId != null && partnerVehicleId != allowedVehicle) {
            throw StateError('Du kan kun se data for din egen bil.');
          }
        }
      }
      return;
    }

    if (me.partnerId != null) {
      if (me.partnerId != partnerId) {
        throw StateError('Du kan kun se data for din egen samarbeidspartner.');
      }
      if (me.partnerVehicleId != null &&
          partnerVehicleId != null &&
          me.partnerVehicleId != partnerVehicleId) {
        throw StateError('Du kan kun se data for din egen bil.');
      }
      return;
    }

    if (me.companyId != null) {
      final partner = await PartnerService.fetchPartner(partnerId);
      if (partner == null || partner.companyId != me.companyId) {
        throw StateError('Ingen tilgang til denne samarbeidspartneren.');
      }
    }
  }

  static List<PartnerRouteShare> routesForPartner(
    List<PartnerRouteShare> routes,
    String partnerId, {
    String? partnerVehicleId,
  }) {
    return routes
        .where((r) {
          if (r.partnerId != partnerId) return false;
          if (partnerVehicleId != null && r.partnerVehicleId != partnerVehicleId) {
            return false;
          }
          return true;
        })
        .toList();
  }

  static List<PartnerVehicle> vehiclesForPartner(
    List<PartnerVehicle> vehicles,
    String partnerId, {
    String? partnerVehicleId,
  }) {
    return vehicles
        .where((v) {
          if (v.partnerId != partnerId) return false;
          if (partnerVehicleId != null && v.id != partnerVehicleId) return false;
          return true;
        })
        .toList();
  }

  static List<PartnerDocument> documentsForPartner(
    List<PartnerDocument> docs,
    String partnerId,
  ) =>
      docs.where((d) => d.partnerId == partnerId).toList();

  /// Økonomisk oppsummering (PDF): kun MAVI superadmin og bil-eier — aldri sjåfør.
  static Future<bool> canViewEconomicSummaries() async {
    final me = await SupabaseService.fetchCurrentUserProfile();
    if (me == null) return false;
    if (me.isSuperAdmin) return true;
    final session = await PartnerService.resolvePortalSession();
    if (session != null) return session.isOwner;
    // Uten session: ikke anta eier (staff har også partner_id uten bil).
    return false;
  }

  static Future<void> assertEconomicSummaryAccess({
    required String partnerId,
  }) async {
    await assertAccess(partnerId: partnerId);
    if (!await canViewEconomicSummaries()) {
      throw StateError(
        'Oppsummering er kun tilgjengelig for bil-eier og MAVI superadmin.',
      );
    }
  }

  static List<PartnerDocument> withoutSummaries(List<PartnerDocument> docs) =>
      docs.where((d) => d.docCategory != 'summary').toList();

  static List<PartnerDocument> onlySummaries(List<PartnerDocument> docs) =>
      docs.where((d) => d.docCategory == 'summary').toList();

  static Future<List<PartnerDocument>> filterDocumentsForViewer(
    List<PartnerDocument> docs, {
    required String partnerId,
    bool includeSummariesIfAllowed = true,
  }) async {
    var list = documentsForPartner(docs, partnerId);
    if (!includeSummariesIfAllowed || !await canViewEconomicSummaries()) {
      list = withoutSummaries(list);
    }
    return list;
  }
}
