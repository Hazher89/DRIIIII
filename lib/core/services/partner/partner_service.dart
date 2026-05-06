import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';

class PartnerService {
  static SupabaseClient get _client => Supabase.instance.client;

  static bool get _ok =>
      !SupabaseConfig.url.startsWith('YOUR_') &&
      !SupabaseConfig.anonKey.startsWith('YOUR_');

  static Future<List<Partner>> fetchPartners({required String companyId}) async {
    if (!_ok) return const [];
    final data = await _client
        .from('partners')
        .select()
        .eq('company_id', companyId)
        .order('name') as List<dynamic>;
    return data.map((e) => Partner.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Partner?> fetchPartner(String id) async {
    if (!_ok) return null;
    final row = await _client.from('partners').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    return Partner.fromJson(row);
  }

  static Future<Partner> createPartner(Partner partner, {String? createdBy}) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    final uid = createdBy ?? _client.auth.currentUser?.id;
    final inserted = await _client
        .from('partners')
        .insert(partner.toInsertJson(partner.companyId, createdBy: uid))
        .select()
        .single();
    return Partner.fromJson(inserted);
  }

  static Future<void> updatePartner(String id, Partner patch) async {
    if (!_ok) return;
    await _client.from('partners').update(patch.toUpdateJson()).eq('id', id);
  }

  static Future<List<PartnerDocument>> fetchDocuments(String partnerId) async {
    if (!_ok) return const [];
    final data = await _client
        .from('partner_documents')
        .select()
        .eq('partner_id', partnerId)
        .order('created_at', ascending: false) as List<dynamic>;
    return data.map((e) => PartnerDocument.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<PartnerDocument> addDocument(PartnerDocument doc, {String? createdBy}) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    final uid = createdBy ?? _client.auth.currentUser?.id;
    final row = await _client
        .from('partner_documents')
        .insert(doc.toInsertJson(createdBy: uid))
        .select()
        .single();
    return PartnerDocument.fromJson(row);
  }

  static Future<void> deleteDocument(String id) async {
    if (!_ok) return;
    await _client.from('partner_documents').delete().eq('id', id);
  }

  static Future<List<PartnerMeeting>> fetchMeetings(String partnerId) async {
    if (!_ok) return const [];
    final data = await _client
        .from('partner_meetings')
        .select()
        .eq('partner_id', partnerId)
        .order('scheduled_at', ascending: false) as List<dynamic>;
    return data.map((e) => PartnerMeeting.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<PartnerMeeting> addMeeting(PartnerMeeting m) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    final row = await _client.from('partner_meetings').insert(m.toInsertJson()).select().single();
    return PartnerMeeting.fromJson(row);
  }

  static Future<List<PartnerRouteShare>> fetchRouteShares(String partnerId) async {
    if (!_ok) return const [];
    final data = await _client
        .from('partner_route_shares')
        .select()
        .eq('partner_id', partnerId)
        .order('share_date', ascending: false) as List<dynamic>;
    return data.map((e) => PartnerRouteShare.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<PartnerRouteShare> addRouteShare(PartnerRouteShare r) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    final row = await _client.from('partner_route_shares').insert(r.toInsertJson()).select().single();
    return PartnerRouteShare.fromJson(row);
  }

  /// Admin: knytt eksisterende profil til partner (krever RLS som tillater oppdatering).
  static Future<void> linkProfileToPartner({
    required String profileId,
    required String partnerId,
  }) async {
    if (!_ok) return;
    await _client.from('profiles').update({
      'partner_id': partnerId,
      'role': 'samarbeidspartner',
      'is_onboarded': true,
      'is_approved': true,
    }).eq('id', profileId);
  }
}
