import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'partner/partner_service.dart';

/// Innlogging og passord for MAVI-ansatte (ansattnummer).
class EmployeeAuthService {
  EmployeeAuthService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static bool get _ok =>
      !SupabaseConfig.url.startsWith('YOUR_') &&
      !SupabaseConfig.anonKey.startsWith('YOUR_');

  /// Standardpassord ved første oppsett (lagret som 000000 i Supabase).
  static const String defaultPasswordHint = '0000';

  /// Supabase Auth krever min. 6 tegn — «0000» mappes til «000000».
  static String normalizePasswordForAuth(String password) {
    final p = password.trim();
    if (p == '0000') return '000000';
    return p;
  }

  static Future<String?> resolveLoginEmail(String employeeNumber) async {
    if (!_ok) return null;
    final n = employeeNumber.trim();
    if (n.isEmpty) return null;
    try {
      final email = await _client.rpc('resolve_employee_login_email', params: {
        'p_employee_number': n,
      });
      if (email == null) return null;
      final s = email.toString().trim();
      return s.isEmpty || s == 'null' ? null : s;
    } catch (_) {
      return null;
    }
  }

  static Future<void> signInWithEmployeeNumber({
    required String employeeNumber,
    required String password,
  }) async {
    final email = await resolveLoginEmail(employeeNumber);
    if (email == null) {
      throw const AuthException('Fant ikke ansattnummer. Sjekk nummeret eller kontakt MAVI.');
    }
    await _client.auth.signInWithPassword(
      email: email,
      password: normalizePasswordForAuth(password),
    );
  }

  static Future<Map<String, dynamic>> changePasswordAndNotifySms({
    required String newPassword,
  }) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    final password = newPassword.trim();
    if (password.length < 6) {
      throw Exception('Passord må være minst 6 tegn');
    }

    Future<Map<String, dynamic>> callEdge() async {
      final token = _client.auth.currentSession?.accessToken;
      if (token == null || token.isEmpty) {
        throw Exception('Økten er utløpt. Logg inn på nytt og prøv igjen.');
      }
      final headers = <String, String>{
        'Authorization': 'Bearer $token',
      };
      final res = await _client.functions.invoke(
        'employee-change-password',
        body: {'new_password': password},
        headers: headers,
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        if (data['error'] != null) {
          throw Exception('${data['error']}');
        }
        return data;
      }
      if (data is Map) return Map<String, dynamic>.from(data);
      return {'ok': true};
    }

    Future<Map<String, dynamic>> fallbackLocalUpdate() async {
      final session = _client.auth.currentSession;
      if (session == null) {
        throw Exception('Økten er utløpt. Logg inn på nytt og prøv igjen.');
      }
      await _client.auth.updateUser(UserAttributes(password: password));
      return {
        'ok': true,
        'message':
            'Passord oppdatert. SMS ble ikke sendt automatisk i denne sesjonen.',
        'sms_error': 'edge_unauthorized',
      };
    }

    try {
      try {
        await _client.auth.refreshSession();
      } catch (_) {}
      return await callEdge();
    } on FunctionException catch (e) {
      final msg = e.details?.toString().toLowerCase() ?? e.toString().toLowerCase();
      final unauthorized = e.status == 401 || e.status == 403 || msg.contains('session_not_found');
      if (!unauthorized) rethrow;
      try {
        await _client.auth.refreshSession();
        return await callEdge();
      } catch (_) {
        return fallbackLocalUpdate();
      }
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('session_not_found') || msg.contains('session') || msg.contains('jwt')) {
        throw Exception('Økten er utløpt. Logg ut og inn igjen, og prøv på nytt.');
      }
      rethrow;
    }
  }

  /// Oppretter Supabase Auth for alle rader i employee_login_accounts uten profile_id.
  static Future<Map<String, dynamic>?> provisionPendingAuthAccounts() async {
    if (!_ok) return null;
    try {
      final res = await _client.functions.invoke('mavi-employees-import', body: {});
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return null;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Flush SMS etter passordendring (samme worker som partner).
  static Future<Map<String, dynamic>?> flushSmsOutbox() =>
      PartnerService.flushSmsOutbox();
}
