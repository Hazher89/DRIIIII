import '../../core/services/supabase_service.dart';

class LmWarehouseService {
  LmWarehouseService._();

  static Future<Map<String, dynamic>?> scanReceive(String barcode) async {
    final cid = await SupabaseService.getCurrentCompanyId();
    if (cid == null) return null;
    final uid = SupabaseService.currentUser?.id;

    final existing = await SupabaseService.client
        .from('lm_warehouse_items')
        .select()
        .eq('company_id', cid)
        .eq('barcode', barcode)
        .maybeSingle();

    if (existing != null) return existing;

    final row = await SupabaseService.client
        .from('lm_warehouse_items')
        .insert({
          'company_id': cid,
          'barcode': barcode,
          'state': 'received',
          if (uid != null) 'received_by': uid,
        })
        .select()
        .single();
    return row;
  }

  static Future<List<Map<String, dynamic>>> search(String query) async {
    final cid = await SupabaseService.getCurrentCompanyId();
    if (cid == null) return [];
    final rows = await SupabaseService.client
        .from('lm_warehouse_items')
        .select()
        .eq('company_id', cid)
        .ilike('barcode', '%$query%')
        .limit(30);
    return List<Map<String, dynamic>>.from(rows as List);
  }
}
