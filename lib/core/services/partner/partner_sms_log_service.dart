import '../../../models/partner_sms_log_entry.dart';
import '../../../models/partner_sms_log_filters.dart';
import '../supabase_service.dart';

/// Partner-modul: henter kun SMS som tilhører samarbeid (RPC-filter).
class PartnerSmsLogService {
  PartnerSmsLogService._();

  static Map<String, dynamic> _filterParams(PartnerSmsLogFilters f) {
    return {
      'p_search': f.search?.trim().isEmpty == true ? null : f.search?.trim(),
      'p_category': f.category,
      'p_status': f.status,
      'p_from_date': f.fromDate?.toUtc().toIso8601String(),
      'p_to_date': f.toDate != null
          ? DateTime(f.toDate!.year, f.toDate!.month, f.toDate!.day, 23, 59, 59)
              .toUtc()
              .toIso8601String()
          : null,
      'p_recipient':
          f.recipient?.trim().isEmpty == true ? null : f.recipient?.trim(),
      'p_sender': f.sender?.trim().isEmpty == true ? null : f.sender?.trim(),
      'p_phone': f.phone?.trim().isEmpty == true ? null : f.phone?.trim(),
      'p_partner_id': f.partnerId?.trim().isEmpty == true ? null : f.partnerId,
    };
  }

  static Future<List<PartnerSmsLogEntry>> fetchLog({
    int limit = 50,
    int offset = 0,
    PartnerSmsLogFilters filters = const PartnerSmsLogFilters(),
  }) async {
    final data = await SupabaseService.client.rpc(
      'list_partner_sms_log',
      params: {
        ..._filterParams(filters),
        'p_limit': limit,
        'p_offset': offset,
        'p_sort': filters.sort,
      },
    );
    return (data as List)
        .map((e) => PartnerSmsLogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<int> countLog({
    PartnerSmsLogFilters filters = const PartnerSmsLogFilters(),
  }) async {
    final data = await SupabaseService.client.rpc(
      'count_partner_sms_log',
      params: _filterParams(filters),
    );
    if (data is int) return data;
    if (data is num) return data.toInt();
    return 0;
  }
}
