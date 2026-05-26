import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../models/lm_fleet_snapshot.dart';

/// Henter sjåfør, bedrift og MAVI-biler fra DriftPro (Supabase master).
class DriftproFleetSyncService {
  DriftproFleetSyncService._();

  static Future<LmFleetSnapshot> syncFromDriftpro() async {
    final cid = await SupabaseService.getCurrentCompanyId();
    if (cid == null) {
      throw StateError('Ingen bedrift — logg inn via DriftPro-konto.');
    }

    final partners = await PartnerService.fetchPartners(companyId: cid);
    final fleet = await PartnerService.fetchCompanyFleet(cid, forPlanning: true);
    final mavi = PartnerService.filterMaviFleetOnly(fleet);

    var driverCount = 0;
    for (final p in partners) {
      final accounts = await PartnerService.fetchPortalAccounts(p.id);
      driverCount += accounts.where((a) => a.partnerVehicleId != null).length;
    }

    final payload = {
      'vehicles': mavi
          .map(
            (r) => {
              'unit': r.vehicle.unitCode,
              'partner': r.partner.name,
              'payload_kg': r.vehicle.payloadKg,
              'driver': r.vehicle.driverName,
            },
          )
          .toList(),
    };

    try {
      await SupabaseService.client.from('lm_fleet_sync_runs').insert({
        'company_id': cid,
        'vehicles_synced': mavi.length,
        'drivers_synced': driverCount,
        'partners_synced': partners.length,
        'payload': payload,
      });
    } catch (_) {
      // Tabell ikke migrert ennå — sync fungerer likevel.
    }

    return LmFleetSnapshot(
      syncedAt: DateTime.now(),
      maviVehicles: mavi,
      partners: partners,
      driverPortalCount: driverCount,
    );
  }
}
