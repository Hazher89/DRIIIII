import '../../../models/sms_log_entry.dart';
import '../../../models/sms_log_filters.dart';
import '../supabase_service.dart';

class SmsLogService {
  SmsLogService._();

  static Map<String, dynamic> _params(SmsLogFilters f, {int? limit, int? offset}) {
    return {
      if (limit != null) 'p_limit': limit,
      if (offset != null) 'p_offset': offset,
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
    };
  }

  static Future<List<SmsLogEntry>> fetchLog({
    int limit = 50,
    int offset = 0,
    SmsLogFilters filters = const SmsLogFilters(),
  }) async {
    final params = _params(filters, limit: limit, offset: offset);
    try {
      final data = await SupabaseService.client.rpc(
        'list_company_sms_log',
        params: params,
      );
      return (data as List)
          .map((e) => SmsLogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Fallback uten nye filter-parametre (gammel RPC)
      final data = await SupabaseService.client.rpc(
        'list_company_sms_log',
        params: {
          'p_limit': limit,
          'p_offset': offset,
          'p_search': params['p_search'],
          'p_category': params['p_category'],
          'p_status': params['p_status'],
        },
      );
      return (data as List)
          .map((e) => SmsLogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  static Future<int> countLog({SmsLogFilters filters = const SmsLogFilters()}) async {
    try {
      final data = await SupabaseService.client.rpc(
        'count_company_sms_log',
        params: _params(filters),
      );
      if (data is int) return data;
      if (data is num) return data.toInt();
      return 0;
    } catch (_) {
      return 0;
    }
  }
}
