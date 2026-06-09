import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/time_clock/time_clock_presence.dart';
import '../../../models/time_clock/time_timesheet_entry.dart';
import '../../../models/time_clock/time_work_type.dart';

class TimeClockService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<Map<String, dynamic>> kioskGetCompany(String slug) async {
    final res = await _client.rpc('kiosk_get_company', params: {'p_slug': slug});
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<Map<String, dynamic>> kioskLogin({
    required String slug,
    required String employeeNumber,
    required String pin,
  }) async {
    final res = await _client.rpc('kiosk_login', params: {
      'p_slug': slug,
      'p_employee_number': employeeNumber.trim(),
      'p_pin': pin,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<Map<String, dynamic>> kioskPunch({
    required String sessionToken,
    String? workTypeId,
  }) async {
    final res = await _client.rpc('kiosk_punch', params: {
      'p_session_token': sessionToken,
      'p_work_type_id': workTypeId,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<Map<String, dynamic>> punchMobile({String? workTypeId}) async {
    final res = await _client.rpc('time_clock_punch_mobile', params: {
      'p_work_type_id': workTypeId,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<List<TimeClockPresence>> listPresence({String? departmentId}) async {
    final res = await _client.rpc('time_clock_list_presence', params: {
      'p_department_id': departmentId,
    });
    final list = res as List<dynamic>? ?? [];
    return list
        .map((e) => TimeClockPresence.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<List<TimeWorkType>> kioskFetchWorkTypes(String sessionToken) async {
    final res = await _client.rpc('kiosk_get_work_types', params: {
      'p_session_token': sessionToken,
    });
    final list = res as List<dynamic>? ?? [];
    return list.map((e) {
      final map = Map<String, dynamic>.from(e as Map);
      map['company_id'] = map['company_id'] ?? '';
      map['category'] = map['category'] ?? 'shift';
      map['is_active'] = true;
      map['sort_order'] = 0;
      return TimeWorkType.fromJson(map);
    }).toList();
  }

  static Future<List<TimeWorkType>> fetchWorkTypes(String companyId) async {
    final data = await _client
        .from('time_work_types')
        .select()
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('sort_order') as List<dynamic>;
    return data.map((e) => TimeWorkType.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  static Future<List<TimeTimesheetEntry>> fetchTimesheetEntries({
    required String profileId,
    required DateTime weekStart,
    required DateTime weekEnd,
  }) async {
    final data = await _client
        .from('time_timesheet_entries')
        .select('*, work_type:time_work_types(code, name, color_hex, payroll_code)')
        .eq('profile_id', profileId)
        .gte('work_date', weekStart.toIso8601String().split('T').first)
        .lte('work_date', weekEnd.toIso8601String().split('T').first)
        .order('work_date')
        .order('created_at') as List<dynamic>;

    return data.map((e) {
      final map = Map<String, dynamic>.from(e);
      final wt = map['work_type'];
      if (wt is Map) {
        map['work_type_code'] = wt['code'];
        map['work_type_name'] = wt['name'];
        map['work_type_color'] = wt['color_hex'];
        map['payroll_code'] = wt['payroll_code'];
      }
      return TimeTimesheetEntry.fromJson(map);
    }).toList();
  }

  static Future<String> upsertEntry(TimeTimesheetEntry entry) async {
    final res = await _client.rpc('time_clock_upsert_entry', params: {
      'p_payload': entry.toUpsertPayload(),
    });
    return res as String;
  }

  static Future<void> deleteEntry(String entryId) async {
    await _client.rpc('time_clock_delete_entry', params: {'p_entry_id': entryId});
  }

  static Future<void> setPin(String profileId, String pin) async {
    await _client.rpc('time_clock_set_pin', params: {
      'p_profile_id': profileId,
      'p_pin': pin,
    });
  }

  static Future<void> grantMobile(String profileId, bool allowed) async {
    await _client.rpc('time_clock_grant_mobile', params: {
      'p_profile_id': profileId,
      'p_allowed': allowed,
    });
  }

  static Future<Map<String, dynamic>> getSettings() async {
    final res = await _client.rpc('time_clock_get_settings');
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<void> updateSettings(Map<String, dynamic> payload) async {
    await _client.rpc('time_clock_update_settings', params: {'p_payload': payload});
  }

  static Future<int> syncDefaultPins() async {
    final res = await _client.rpc('time_clock_sync_default_pins');
    return res as int? ?? 0;
  }

  static Future<Map<String, dynamic>?> fetchMyClockState() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final data = await _client
        .from('time_clock_state')
        .select('*, work_type:time_work_types(code, name)')
        .eq('profile_id', userId)
        .maybeSingle();

    if (data == null) return null;
    return Map<String, dynamic>.from(data);
  }

  static Future<bool> hasMobileAccess() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final data = await _client
        .from('profiles')
        .select('time_clock_mobile_allowed')
        .eq('id', userId)
        .maybeSingle();

    return data?['time_clock_mobile_allowed'] as bool? ?? false;
  }

  static int clockedInCount(List<TimeClockPresence> list) =>
      list.where((e) => e.isClockedIn).length;
}
