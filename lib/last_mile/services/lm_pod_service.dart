import '../../core/services/supabase_service.dart';

class LmPodService {
  LmPodService._();

  static Future<void> recordDelivery({
    required String routeStopId,
    required String signerName,
    List<String> photoPaths = const [],
    double? lat,
    double? lng,
    String? notes,
  }) async {
    final cid = await SupabaseService.getCurrentCompanyId();
    if (cid == null) return;

    await SupabaseService.client.from('lm_pod_records').insert({
      'company_id': cid,
      'route_stop_id': routeStopId,
      'signer_name': signerName,
      'photo_storage_paths': photoPaths,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (notes != null) 'notes': notes,
    });

    final stop = await SupabaseService.client
        .from('lm_route_stops')
        .select('lm_order_id')
        .eq('id', routeStopId)
        .maybeSingle();

    await SupabaseService.client
        .from('lm_route_stops')
        .update({'status': 'completed'})
        .eq('id', routeStopId);

    final oid = stop?['lm_order_id'] as String?;
    if (oid != null) {
      await SupabaseService.client.from('lm_orders').update({'status': 'delivered'}).eq('id', oid);
    }
  }
}
