import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/attendance/employee_attendance.dart';
import '../supabase_service.dart';

class AttendanceService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<EmployeeAttendance?> getMyAttendance() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final data = await _client
        .from('employee_attendance')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (data == null) return null;
    return EmployeeAttendance.fromJson(data);
  }

  static Future<List<EmployeeAttendance>> getOnDutyEmployees(String companyId) async {
    final data = await _client
        .from('employee_attendance')
        .select('*, profiles(full_name, avatar_url)')
        .eq('company_id', companyId)
        .eq('status', 'on_duty') as List<dynamic>;

    return data.map((e) => EmployeeAttendance.fromJson(e)).toList();
  }
  
  static Future<List<EmployeeAttendance>> getAllEmployeesAttendance(String companyId) async {
    final data = await _client
        .from('employee_attendance')
        .select('*, profiles(full_name, avatar_url)')
        .eq('company_id', companyId) as List<dynamic>;

    return data.map((e) => EmployeeAttendance.fromJson(e)).toList();
  }

  static Future<void> toggleStatus(AttendanceStatus newStatus) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final companyId = await SupabaseService.getCurrentCompanyId();
    if (companyId == null) return;

    final now = DateTime.now().toIso8601String();
    
    final Map<String, dynamic> upsertData = {
      'user_id': user.id,
      'company_id': companyId,
      'status': newStatus.name,
      'last_updated': now,
    };

    if (newStatus == AttendanceStatus.on_duty) {
      upsertData['check_in_at'] = now;
      upsertData['check_out_at'] = null;
    } else {
      upsertData['check_out_at'] = now;
    }

    await _client.from('employee_attendance').upsert(upsertData);
    
    // Log it
    await _client.from('attendance_logs').insert({
      'user_id': user.id,
      'company_id': companyId,
      'action': newStatus.name,
      'timestamp': now,
    });
  }
}
