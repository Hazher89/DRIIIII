import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/tidsbanken_presence.dart';
import '../supabase_service.dart';

class TidsbankenPresenceService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<bool> isEnabledForCompany(String companyId) async {
    final row = await _client
        .from('companies')
        .select('tidsbanken_enabled')
        .eq('id', companyId)
        .maybeSingle();
    return row?['tidsbanken_enabled'] == true;
  }

  static Future<void> setEnabled(bool enabled) async {
    await _client.rpc('set_company_tidsbanken_enabled', params: {'p_enabled': enabled});
  }

  static Future<List<TidsbankenPresence>> fetchPresence(String companyId) async {
    final data = await _client
        .from('tidsbanken_presence')
        .select()
        .eq('company_id', companyId)
        .order('last_name') as List<dynamic>;
    return data
        .map((e) => TidsbankenPresence.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<TidsbankenSyncState?> fetchSyncState(String companyId) async {
    final row = await _client
        .from('tidsbanken_sync_state')
        .select()
        .eq('company_id', companyId)
        .maybeSingle();
    if (row == null) return null;
    return TidsbankenSyncState.fromJson(row);
  }

  /// Henter ny data fra Tidsbanken (edge function tidsbanken-sync).
  static Future<({bool ok, String? error, int? clockedIn, int? total, List<String>? loginSteps})> syncNow() async {
    try {
      final res = await _client.functions.invoke(
        'tidsbanken-sync',
        body: const {},
      );
      final data = res.data;
      if (data is Map && data['error'] != null) {
        return (ok: false, error: data['error'].toString(), clockedIn: null, total: null, loginSteps: null);
      }
      if (data is Map && data['ok'] == true) {
        final steps = data['login_steps'];
        return (
          ok: true,
          error: null,
          clockedIn: data['clocked_in'] as int?,
          total: data['total'] as int?,
          loginSteps: steps is List ? steps.map((e) => e.toString()).toList() : null,
        );
      }
      return (ok: true, error: null, clockedIn: null, total: null, loginSteps: null);
    } on FunctionException catch (e) {
      final details = e.details;
      final msg = details is Map && details['error'] != null
          ? details['error'].toString()
          : e.reasonPhrase ?? e.toString();
      return (ok: false, error: msg, clockedIn: null, total: null, loginSteps: null);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('Failed to fetch')) {
        return (
          ok: false,
          error:
              'Kunne ikke nå tidsbanken-sync på Supabase. Sjekk at funksjonen er deployet og at du er innlogget.',
          clockedIn: null,
          total: null,
          loginSteps: null,
        );
      }
      return (ok: false, error: msg, clockedIn: null, total: null, loginSteps: null);
    }
  }

  static Future<({List<TidsbankenPresence> rows, TidsbankenSyncState? sync})> loadForCurrentCompany({
    bool trySync = false,
  }) async {
    final companyId = await SupabaseService.getCurrentCompanyId();
    if (companyId == null) {
      return (rows: <TidsbankenPresence>[], sync: null);
    }
    if (trySync && await isEnabledForCompany(companyId)) {
      await syncNow();
    }
    final rows = await fetchPresence(companyId);
    final sync = await fetchSyncState(companyId);
    return (rows: rows, sync: sync);
  }
}
