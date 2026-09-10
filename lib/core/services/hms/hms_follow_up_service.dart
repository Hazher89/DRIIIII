import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/hms/hms_follow_up.dart';
import '../supabase_service.dart';

class HmsFollowUpService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<String> createAndNotify({
    required String companyId,
    required String module,
    required String referenceType,
    required String referenceId,
    required String title,
    String? summary,
    int deviationCount = 1,
    DateTime? dueAt,
    required List<String> recipientIds,
    bool sendEmail = true,
    bool sendPush = true,
  }) async {
    final ids = recipientIds.toSet().where((e) => e.trim().isNotEmpty).toList();
    if (ids.isEmpty) {
      throw StateError('Velg minst én mottaker');
    }
    final due = dueAt == null
        ? null
        : '${dueAt.year.toString().padLeft(4, '0')}-'
            '${dueAt.month.toString().padLeft(2, '0')}-'
            '${dueAt.day.toString().padLeft(2, '0')}';

    final res = await _client.rpc(
      'hms_create_follow_up_notify',
      params: {
        'p_company_id': companyId,
        'p_module': module,
        'p_reference_type': referenceType,
        'p_reference_id': referenceId,
        'p_title': title,
        'p_summary': summary,
        'p_deviation_count': deviationCount,
        'p_due_at': due,
        'p_recipient_ids': ids,
        'p_send_email': sendEmail,
        'p_send_push': sendPush,
      },
    );
    return res.toString();
  }

  static Future<HmsFollowUp?> close({
    required String followUpId,
    String? notes,
  }) async {
    final res = await _client.rpc(
      'hms_close_follow_up',
      params: {
        'p_follow_up_id': followUpId,
        'p_notes': notes,
      },
    );
    if (res is Map<String, dynamic>) {
      return HmsFollowUp.fromJson(res);
    }
    if (res is Map) {
      return HmsFollowUp.fromJson(Map<String, dynamic>.from(res));
    }
    return null;
  }

  static Future<List<HmsFollowUp>> fetchForReference({
    required String referenceType,
    required String referenceId,
    bool openOnly = false,
  }) async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      var q = _client
          .from('hms_follow_ups')
          .select('*, hms_follow_up_recipients(profile_id)')
          .eq('reference_type', referenceType)
          .eq('reference_id', referenceId);
      if (openOnly) {
        q = q.eq('status', 'open');
      }
      final data =
          await q.order('created_at', ascending: false) as List<dynamic>;
      return data
          .map((e) => HmsFollowUp.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<HmsFollowUp>> fetchOpenForCompany(String companyId) async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final data = await _client
          .from('hms_follow_ups')
          .select('*, hms_follow_up_recipients(profile_id)')
          .eq('company_id', companyId)
          .eq('status', 'open')
          .order('follow_up_due_at', ascending: true) as List<dynamic>;
      return data
          .map((e) => HmsFollowUp.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
