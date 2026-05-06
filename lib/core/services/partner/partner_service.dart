import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';

import '../../config/supabase_config.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/fleet_shift.dart';
import 'fleet_shift_seed.dart';

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

  static Future<List<PartnerDocument>> fetchDocuments(
    String partnerId, {
    List<String>? docCategories,
  }) async {
    if (!_ok) return const [];
    var q = _client.from('partner_documents').select().eq('partner_id', partnerId);
    if (docCategories != null && docCategories.isNotEmpty) {
      q = q.inFilter('doc_category', docCategories);
    }
    final data = await q.order('created_at', ascending: false) as List<dynamic>;
    return data.map((e) => PartnerDocument.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Sender magic link / OTP til portal-e-post (ingen passord i skjema). Krever e-postmal i Supabase.
  static Future<void> sendPartnerPortalMagicLink({
    required String email,
    String? redirectTo,
  }) async {
    if (!_ok) return;
    final em = email.trim().toLowerCase();
    if (!em.contains('@')) return;
    await _client.auth.signInWithOtp(
      email: em,
      emailRedirectTo: redirectTo ?? 'https://driftpro.no',
      shouldCreateUser: true,
    );
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

  static Future<void> updateRouteAcknowledgement({
    required String routeShareId,
    required bool accepted,
    String? comment,
  }) async {
    if (!_ok) return;
    await _client.from('partner_route_shares').update({
      'ack_status': accepted ? 'accepted' : 'rejected',
      'ack_at': DateTime.now().toIso8601String(),
      'ack_by': _client.auth.currentUser?.id,
      'ack_comment': comment,
    }).eq('id', routeShareId);
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

  static Future<List<PartnerVehicle>> fetchVehicles(String partnerId) async {
    if (!_ok) return const [];
    final data = await _client
        .from('partner_vehicles')
        .select()
        .eq('partner_id', partnerId)
        .order('unit_code', ascending: true) as List<dynamic>;
    return data.map((e) => PartnerVehicle.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> replaceVehicles({
    required String partnerId,
    required String companyId,
    required List<PartnerVehicle> vehicles,
  }) async {
    if (!_ok) return;
    await _client.from('partner_vehicles').delete().eq('partner_id', partnerId);
    if (vehicles.isEmpty) return;
    final payload = vehicles
        .map((v) => {
              'partner_id': partnerId,
              'company_id': companyId,
              'unit_code': v.unitCode,
              'registration_number': v.registrationNumber,
              'notes': v.notes,
            })
        .toList();
    await _client.from('partner_vehicles').insert(payload);
  }

  static Future<void> upsertPortalAccount({
    required String partnerId,
    required String companyId,
    required String username,
    required String loginEmail,
    String? profileId,
  }) async {
    if (!_ok) return;
    final normalizedUsername = username.toLowerCase().trim();
    final normalizedEmail = loginEmail.toLowerCase().trim();

    // Robust i både nye og eksisterende databaser:
    // ikke avhengig av at ON CONFLICT matcher eksakt unik constraint.
    final existingByUsername = await _client
        .from('partner_portal_accounts')
        .select('id')
        .eq('username', normalizedUsername)
        .maybeSingle();

    if (existingByUsername != null) {
      await _client.from('partner_portal_accounts').update({
        'partner_id': partnerId,
        'company_id': companyId,
        'login_email': normalizedEmail,
        'profile_id': profileId,
        'is_active': true,
      }).eq('id', existingByUsername['id'] as String);
      return;
    }

    final existingByEmail = await _client
        .from('partner_portal_accounts')
        .select('id')
        .eq('login_email', normalizedEmail)
        .maybeSingle();

    if (existingByEmail != null) {
      await _client.from('partner_portal_accounts').update({
        'partner_id': partnerId,
        'company_id': companyId,
        'username': normalizedUsername,
        'profile_id': profileId,
        'is_active': true,
      }).eq('id', existingByEmail['id'] as String);
      return;
    }

    await _client.from('partner_portal_accounts').insert({
      'partner_id': partnerId,
      'company_id': companyId,
      'username': normalizedUsername,
      'login_email': normalizedEmail,
      'profile_id': profileId,
      'is_active': true,
    });
  }

  static Future<String?> resolveLoginIdentifierToEmail(String identifier) async {
    final input = identifier.trim();
    if (input.contains('@')) return input;
    if (!_ok) return null;
    try {
      final val = await _client.rpc('resolve_partner_login_email', params: {
        'p_username': input.toLowerCase(),
      });
      if (val is String && val.trim().isNotEmpty) return val.trim();
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> uploadPartnerRoutePdf({
    required String storagePath,
    required Uint8List bytes,
  }) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    await _client.storage.from('documents').uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'application/pdf',
          ),
        );
  }

  static Future<String> getRoutePdfSignedUrl(String storagePath) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    return _client.storage.from('documents').createSignedUrl(storagePath, 3600);
  }

  static Future<void> uploadPartnerDocumentPdf({
    required String storagePath,
    required Uint8List bytes,
  }) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    await _client.storage.from('documents').uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'application/pdf',
          ),
        );
  }

  static Future<String> getDocumentPdfSignedUrl(String storagePath) async {
    return getRoutePdfSignedUrl(storagePath);
  }

  // ── Flåte / skift / sporingsdashboard ─────────────────────────────────

  static Future<void> ensureDefaultFleetShifts(String companyId) async {
    if (!_ok) return;
    final probe = await _client
        .from('fleet_shift_definitions')
        .select('id')
        .eq('company_id', companyId)
        .limit(1) as List<dynamic>;
    if (probe.isNotEmpty) return;
    final rows = FleetShiftSeed.buildRows(companyId);
    await _client.from('fleet_shift_definitions').insert(rows);
  }

  static Future<List<FleetShiftDefinition>> fetchFleetShifts(String companyId) async {
    if (!_ok) return const [];
    final data = await _client
        .from('fleet_shift_definitions')
        .select()
        .eq('company_id', companyId)
        .eq('is_archived', false)
        .order('sort_order') as List<dynamic>;
    return data.map((e) => FleetShiftDefinition.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<List<FleetPartnerVehicleRow>> fetchCompanyFleet(String companyId) async {
    if (!_ok) return const [];
    final partners = await fetchPartners(companyId: companyId);
    final out = <FleetPartnerVehicleRow>[];
    for (final p in partners) {
      for (final v in await fetchVehicles(p.id)) {
        out.add(FleetPartnerVehicleRow(partner: p, vehicle: v));
      }
    }
    return out;
  }

  static Future<List<PartnerVehicleFleetSnapshot>> fetchFleetSnapshots({
    required String companyId,
    required DateTime date,
    required String shiftId,
  }) async {
    if (!_ok) return const [];
    final d = date.toIso8601String().split('T').first;
    final data = await _client
        .from('partner_vehicle_fleet_snapshots')
        .select()
        .eq('company_id', companyId)
        .eq('snapshot_date', d)
        .eq('shift_id', shiftId) as List<dynamic>;
    return data.map((e) => PartnerVehicleFleetSnapshot.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<List<PartnerVehicleFleetSnapshot>> fetchFleetSnapshotsRange({
    required String companyId,
    required DateTime from,
    required DateTime to,
  }) async {
    if (!_ok) return const [];
    final a = from.toIso8601String().split('T').first;
    final b = to.toIso8601String().split('T').first;
    final data = await _client
        .from('partner_vehicle_fleet_snapshots')
        .select()
        .eq('company_id', companyId)
        .gte('snapshot_date', a)
        .lte('snapshot_date', b) as List<dynamic>;
    return data.map((e) => PartnerVehicleFleetSnapshot.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> upsertFleetSnapshot(PartnerVehicleFleetSnapshot snap) async {
    if (!_ok) return;
    await _client.from('partner_vehicle_fleet_snapshots').upsert(
          snap.toUpsertJson(),
          onConflict: 'partner_vehicle_id,snapshot_date,shift_id',
        );
  }

  /// Etter massefordeling: biler med rute = har_rute, øvrige aktive biler = ledig.
  static Future<void> syncFleetAfterMassRoute({
    required String companyId,
    required DateTime date,
    required String shiftId,
    required Map<String, String?> vehicleIdToRouteShareId,
  }) async {
    if (!_ok) return;
    final fleet = await fetchCompanyFleet(companyId);
    final d = date.toIso8601String().split('T').first;
    for (final row in fleet) {
      final vid = row.vehicle.id;
      final shareId = vehicleIdToRouteShareId[vid];
      final snap = PartnerVehicleFleetSnapshot(
        id: '',
        companyId: companyId,
        partnerVehicleId: vid,
        snapshotDate: DateTime.parse(d),
        shiftId: shiftId,
        status: shareId != null ? 'har_rute' : 'ledig',
        partnerRouteShareId: shareId,
        notes: null,
        createdAt: DateTime.now(),
      );
      await upsertFleetSnapshot(snap);
    }
  }

  static Future<List<PartnerRouteShare>> fetchRouteSharesForCompany(
    String companyId, {
    int limit = 800,
  }) async {
    if (!_ok) return const [];
    final data = await _client
        .from('partner_route_shares')
        .select()
        .eq('company_id', companyId)
        .order('created_at', ascending: false)
        .limit(limit) as List<dynamic>;
    return data.map((e) => PartnerRouteShare.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<FleetShiftDefinition> createFleetShift({
    required String companyId,
    required String name,
    String? description,
    required String colorHex,
    String? regionGroup,
    String? timeBand,
    String shiftKind = 'route_ops',
  }) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    final maxSort = await _client
        .from('fleet_shift_definitions')
        .select('sort_order')
        .eq('company_id', companyId)
        .order('sort_order', ascending: false)
        .limit(1) as List<dynamic>;
    final next = maxSort.isEmpty ? 0 : (maxSort.first['sort_order'] as int? ?? 0) + 1;
    final row = await _client
        .from('fleet_shift_definitions')
        .insert({
          'company_id': companyId,
          'name': name,
          'description': description,
          'color_hex': colorHex,
          'region_group': regionGroup,
          'time_band': timeBand,
          'shift_kind': shiftKind,
          'sort_order': next,
        })
        .select()
        .single();
    return FleetShiftDefinition.fromJson(row);
  }
}

/// Én linje i flåteoversikten (partner + kjøretøy).
class FleetPartnerVehicleRow {
  final Partner partner;
  final PartnerVehicle vehicle;
  const FleetPartnerVehicleRow({required this.partner, required this.vehicle});
}
