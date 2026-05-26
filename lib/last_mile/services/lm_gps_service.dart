import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/supabase_service.dart';

class LmGpsService {
  LmGpsService._();

  static Future<bool> ensurePermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
  }

  static Future<void> uploadPosition({
    required String partnerVehicleId,
    String? routeId,
    String? driverProfileId,
  }) async {
    final cid = await SupabaseService.getCurrentCompanyId();
    if (cid == null) return;

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    await SupabaseService.client.from('lm_gps_positions').insert({
      'company_id': cid,
      'partner_vehicle_id': partnerVehicleId,
      if (routeId != null) 'route_id': routeId,
      if (driverProfileId != null) 'driver_profile_id': driverProfileId,
      'lat': pos.latitude,
      'lng': pos.longitude,
      'speed_kmh': pos.speed * 3.6,
      'heading_deg': pos.heading,
    });
  }

  static Stream<List<Map<String, dynamic>>> subscribeFleetPositions(String companyId) {
    return Supabase.instance.client
        .from('lm_gps_positions')
        .stream(primaryKey: ['id'])
        .eq('company_id', companyId)
        .order('recorded_at', ascending: false)
        .limit(50)
        .map((rows) => List<Map<String, dynamic>>.from(rows));
  }

  static Future<Map<String, dynamic>?> latestForVehicle(String vehicleId) async {
    final rows = await SupabaseService.client
        .from('lm_gps_positions')
        .select()
        .eq('partner_vehicle_id', vehicleId)
        .order('recorded_at', ascending: false)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return list.first as Map<String, dynamic>;
  }
}
