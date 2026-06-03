import '../../../models/email_log_entry.dart';
import '../../../models/email_log_filters.dart';
import '../supabase_service.dart';

class EmailLogService {
  EmailLogService._();

  static Map<String, dynamic> _params(
    EmailLogFilters f, {
    int? limit,
    int? offset,
  }) {
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
    };
  }

  static Future<List<EmailLogEntry>> fetchLog({
    int limit = 50,
    int offset = 0,
    EmailLogFilters filters = const EmailLogFilters(),
  }) async {
    final data = await SupabaseService.client.rpc(
      'list_company_email_log',
      params: _params(filters, limit: limit, offset: offset),
    );
    return (data as List)
        .map((e) => EmailLogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<int> countLog({
    EmailLogFilters filters = const EmailLogFilters(),
  }) async {
    final c = await SupabaseService.client.rpc(
      'count_company_email_log',
      params: _params(filters),
    );
    return (c as num).toInt();
  }
}
