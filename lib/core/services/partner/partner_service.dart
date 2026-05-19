import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';

import '../../config/app_origin.dart';
import '../../config/supabase_config.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../utils/portal_credentials.dart';
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

  static Future<void> deletePartner(String id) async {
    if (!_ok) return;
    await _client.from('partners').delete().eq('id', id);
  }

  static Future<int> notifyMeetingSms({
    required String partnerId,
    required String message,
  }) async {
    if (!_ok) return 0;
    try {
      final n = await _client.rpc('notify_partner_meeting_sms', params: {
        'p_partner_id': partnerId,
        'p_message': message,
      });
      return (n as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<String> uploadVehicleImage({
    required String companyId,
    required String partnerId,
    required String unitCode,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    final path =
        '$companyId/partners/$partnerId/vehicles/${unitCode}_${DateTime.now().millisecondsSinceEpoch}_$fileName';
    await _client.storage.from('documents').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return path;
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
      emailRedirectTo: redirectTo ?? appAuthRedirectOrigin,
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

  static Future<List<PartnerRouteShare>> fetchRouteShares(
    String partnerId, {
    String? partnerVehicleId,
    bool sentOnly = false,
  }) async {
    if (!_ok) return const [];
    var query = _client.from('partner_route_shares').select().eq('partner_id', partnerId);
    if (partnerVehicleId != null) {
      query = query.eq('partner_vehicle_id', partnerVehicleId);
    }
    if (sentOnly) {
      try {
        query = query.eq('dispatch_status', 'sent');
      } catch (_) {}
    }
    final data = await query.order('share_date', ascending: false) as List<dynamic>;
    return data.map((e) => PartnerRouteShare.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<PartnerRouteShare> addRouteShare(PartnerRouteShare r) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    final row = await _client.from('partner_route_shares').insert(r.toInsertJson()).select().single();
    return PartnerRouteShare.fromJson(row);
  }

  static Future<void> updateRouteShareFields(
    String shareId,
    Map<String, dynamic> fields,
  ) async {
    if (!_ok) return;
    await _client.from('partner_route_shares').update(fields).eq('id', shareId);
  }

  static Future<List<PartnerRouteShare>> fetchStagedRouteShares(String companyId) async {
    if (!_ok) return const [];
    try {
      final data = await _client
          .from('partner_route_shares')
          .select()
          .eq('company_id', companyId)
          .eq('dispatch_status', 'staged')
          .order('created_at', ascending: false) as List<dynamic>;
      return data.map((e) => PartnerRouteShare.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      final all = await fetchRouteSharesForCompany(companyId, limit: 500);
      return all.where((s) => s.shiftId == null && s.ackStatus == 'pending').toList();
    }
  }

  /// Send staged ruter — hver rute kan ha eget skift og starttid.
  static Future<void> dispatchRouteShares({
    required String companyId,
    required Map<String, String> shareIdToShiftId,
    required DateTime date,
    Map<String, DateTime?> shareIdToStartAt = const {},
  }) async {
    if (!_ok || shareIdToShiftId.isEmpty) return;
    final d = date.toIso8601String().split('T').first;

    for (final entry in shareIdToShiftId.entries) {
      final startAt = shareIdToStartAt[entry.key];
      final patch = <String, dynamic>{
        'dispatch_status': 'sent',
        'shift_id': entry.value,
        'share_date': d,
      };
      if (startAt != null) {
        patch['route_start_at'] = startAt.toUtc().toIso8601String();
      }
      await _client.from('partner_route_shares').update(patch).eq('id', entry.key);

      final row = await _client
          .from('partner_route_shares')
          .select('partner_vehicle_id')
          .eq('id', entry.key)
          .maybeSingle();
      final vid = row?['partner_vehicle_id'] as String?;
      if (vid == null) continue;

      await upsertFleetSnapshot(
        PartnerVehicleFleetSnapshot(
          id: '',
          companyId: companyId,
          partnerVehicleId: vid,
          snapshotDate: DateTime.parse(d),
          shiftId: entry.value,
          status: 'har_rute',
          partnerRouteShareId: entry.key,
          notes: startAt != null
              ? 'Start ${startAt.hour.toString().padLeft(2, '0')}:${startAt.minute.toString().padLeft(2, '0')}'
              : null,
          createdAt: DateTime.now(),
        ),
      );

      try {
        await _client.rpc('notify_partner_route_assigned_sms', params: {
          'p_route_share_id': entry.key,
        });
      } catch (_) {}
    }
  }

  static String suggestedPortalLoginEmail({
    required String username,
    required String companyId,
  }) {
    final user = username.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.-]'), '');
    final cid = companyId.replaceAll('-', '').substring(0, 8);
    return '$user@mavi.$cid.portal';
  }

  static Future<List<PartnerPortalAccount>> fetchPortalAccounts(String partnerId) async {
    if (!_ok) return const [];
    try {
      final data = await _client
          .from('partner_portal_accounts')
          .select()
          .eq('partner_id', partnerId)
          .eq('is_active', true) as List<dynamic>;
      return data.map((e) => PartnerPortalAccount.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<PortalProvisionResult> provisionDriverPortal({
    required String partnerId,
    required String companyId,
    required String partnerVehicleId,
    required String unitCode,
    required String phone,
    bool regeneratePassword = false,
  }) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    final username = PortalCredentials.driverUsername(unitCode);
    final password = PortalCredentials.generatePassword();
    final loginEmail = PortalCredentials.loginEmail(
      username: username,
      companyId: companyId,
      isOwner: false,
    );
    final res = await _invokePortalProvision(
      partnerId: partnerId,
      companyId: companyId,
      partnerVehicleId: partnerVehicleId,
      username: username,
      loginEmail: loginEmail,
      phone: phone,
      password: password,
      accountKind: 'driver',
      sendCredentialsSms: true,
      regeneratePassword: regeneratePassword,
    );
    return res;
  }

  static Future<PortalProvisionResult> provisionOwnerPortal({
    required String partnerId,
    required String companyId,
    required String phone,
    bool regeneratePassword = false,
  }) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    final username = PortalCredentials.ownerUsername(partnerId);
    final password = PortalCredentials.generatePassword();
    final loginEmail = PortalCredentials.loginEmail(
      username: username,
      companyId: companyId,
      isOwner: true,
    );
    return _invokePortalProvision(
      partnerId: partnerId,
      companyId: companyId,
      username: username,
      loginEmail: loginEmail,
      phone: phone,
      password: password,
      accountKind: 'owner',
      sendCredentialsSms: true,
      regeneratePassword: regeneratePassword,
    );
  }

  static Future<PortalProvisionResult> _invokePortalProvision({
    required String partnerId,
    required String companyId,
    String? partnerVehicleId,
    required String username,
    required String loginEmail,
    required String phone,
    required String password,
    required String accountKind,
    bool sendCredentialsSms = true,
    bool regeneratePassword = false,
  }) async {
    final response = await _client.functions.invoke(
      'partner-portal-provision',
      body: {
        'partner_id': partnerId,
        'company_id': companyId,
        if (partnerVehicleId != null) 'partner_vehicle_id': partnerVehicleId,
        'username': username,
        'login_email': loginEmail,
        'phone': phone.trim(),
        'password': password,
        'account_kind': accountKind,
        'send_credentials_sms': sendCredentialsSms,
        'regenerate_password': regeneratePassword,
      },
    );
    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (data['error'] != null) {
        throw Exception(data['error'].toString());
      }
      return PortalProvisionResult(
        username: (data['username'] as String?) ?? username,
        loginEmail: (data['login_email'] as String?) ?? loginEmail,
        password: (data['password'] as String?) ?? password,
        smsSent: data['sms_sent'] == true,
      );
    }
    return PortalProvisionResult(
      username: username,
      loginEmail: loginEmail,
      password: password,
    );
  }

  static Future<PartnerPortalAccount?> fetchOwnerPortalAccount(String partnerId) async {
    final accounts = await fetchPortalAccounts(partnerId);
    for (final a in accounts) {
      if (a.isOwner) return a;
    }
    return null;
  }

  static Future<void> deleteDriverPortal({
    required String partnerVehicleId,
    required String partnerId,
    required String companyId,
  }) async {
    if (!_ok) return;
    try {
      await _client.functions.invoke(
        'partner-portal-provision',
        body: {
          'partner_id': partnerId,
          'company_id': companyId,
          'partner_vehicle_id': partnerVehicleId,
          'account_kind': 'driver',
          'delete_account': true,
        },
      );
    } catch (_) {}
    await _client
        .from('partner_portal_accounts')
        .update({'is_active': false})
        .eq('partner_vehicle_id', partnerVehicleId);
  }

  static Future<void> deleteOwnerPortal({
    required String partnerId,
    required String companyId,
  }) async {
    if (!_ok) return;
    try {
      await _client.functions.invoke(
        'partner-portal-provision',
        body: {
          'partner_id': partnerId,
          'company_id': companyId,
          'account_kind': 'owner',
          'delete_account': true,
        },
      );
    } catch (_) {}
    await _client
        .from('partner_portal_accounts')
        .update({'is_active': false})
        .eq('partner_id', partnerId)
        .eq('account_kind', 'owner');
  }

  static Future<PartnerFriRequest> createFriRequest({
    required String companyId,
    required String partnerId,
    required String? partnerVehicleId,
    required DateTime requestDate,
    String? reason,
  }) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    final row = await _client
        .from('partner_fri_requests')
        .insert({
          'company_id': companyId,
          'partner_id': partnerId,
          'partner_vehicle_id': partnerVehicleId,
          'request_date': requestDate.toIso8601String().split('T').first,
          'reason': reason,
          'requested_by': _client.auth.currentUser?.id,
        })
        .select()
        .single();
    return PartnerFriRequest.fromJson(row);
  }

  static Future<List<PartnerFriRequest>> fetchFriRequests({
    String? companyId,
    String? partnerId,
    String? status,
  }) async {
    if (!_ok) return const [];
    try {
      var q = _client.from('partner_fri_requests').select();
      if (companyId != null) q = q.eq('company_id', companyId);
      if (partnerId != null) q = q.eq('partner_id', partnerId);
      if (status != null) q = q.eq('status', status);
      final data = await q.order('created_at', ascending: false) as List<dynamic>;
      return data.map((e) => PartnerFriRequest.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> reviewFriRequest({
    required String requestId,
    required String companyId,
    required bool approve,
    String? note,
  }) async {
    if (!_ok) return;
    final reqRow = await _client.from('partner_fri_requests').select().eq('id', requestId).maybeSingle();
    if (reqRow == null) return;

    await _client.from('partner_fri_requests').update({
      'status': approve ? 'approved' : 'rejected',
      'reviewed_by': _client.auth.currentUser?.id,
      'reviewed_at': DateTime.now().toIso8601String(),
      'review_note': note,
    }).eq('id', requestId);

    if (!approve) return;
    final vid = reqRow['partner_vehicle_id'] as String?;
    if (vid == null) return;

    final requestDate = DateTime.parse(reqRow['request_date'] as String);
    final shifts = await fetchFleetShifts(companyId);
    FleetShiftDefinition? fri;
    for (final s in shifts) {
      if (s.name.toLowerCase() == 'fri') {
        fri = s;
        break;
      }
    }
    if (fri == null) return;

    await upsertFleetSnapshot(
      PartnerVehicleFleetSnapshot(
        id: '',
        companyId: companyId,
        partnerVehicleId: vid,
        snapshotDate: requestDate,
        shiftId: fri.id,
        status: 'fri',
        partnerRouteShareId: null,
        notes: 'Godkjent fri${note != null && note.isNotEmpty ? ': $note' : ''}',
        createdAt: DateTime.now(),
      ),
    );
  }

  static Future<void> saveRoutePdfSearchText(String shareId, String text) async {
    if (!_ok || text.isEmpty) return;
    final trimmed = text.length > 120000 ? text.substring(0, 120000) : text;
    try {
      await updateRouteShareFields(shareId, {'pdf_search_text': trimmed});
    } catch (_) {
      // Kolonne finnes kanskje ikke før migrering er kjørt
    }
  }

  static Future<List<PartnerRouteShare>> searchRoutePdfText(
    String companyId,
    String query, {
    int limit = 40,
  }) async {
    if (!_ok || query.trim().length < 2) return const [];
    final q = query.trim();
    try {
      final data = await _client
          .from('partner_route_shares')
          .select()
          .eq('company_id', companyId)
          .ilike('pdf_search_text', '%$q%')
          .order('created_at', ascending: false)
          .limit(limit) as List<dynamic>;
      return data.map((e) => PartnerRouteShare.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      final all = await fetchRouteSharesForCompany(companyId, limit: 800);
      final lower = q.toLowerCase();
      return all
          .where((s) =>
              (s.pdfSearchText?.toLowerCase().contains(lower) ?? false) ||
              (s.title?.toLowerCase().contains(lower) ?? false))
          .take(limit)
          .toList();
    }
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
    final existing = await fetchVehicles(partnerId);
    final keepUnits = vehicles.map((v) => v.unitCode.toUpperCase()).toSet();

    for (final old in existing) {
      if (!keepUnits.contains(old.unitCode.toUpperCase())) {
        await _client.from('partner_vehicles').delete().eq('id', old.id);
      }
    }

    if (vehicles.isEmpty) return;

    final payload = vehicles.map((v) => v.toUpsertJson()).toList();
    await _client.from('partner_vehicles').upsert(
          payload,
          onConflict: 'partner_id,unit_code',
        );
  }

  static Future<void> upsertPortalAccount({
    required String partnerId,
    required String companyId,
    required String username,
    required String loginEmail,
    String? profileId,
    String? partnerVehicleId,
    String? phone,
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
        if (partnerVehicleId != null) 'partner_vehicle_id': partnerVehicleId,
        if (phone != null) 'phone': phone,
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
        if (partnerVehicleId != null) 'partner_vehicle_id': partnerVehicleId,
        if (phone != null) 'phone': phone,
        'is_active': true,
      }).eq('id', existingByEmail['id'] as String);
      return;
    }

    if (partnerVehicleId != null) {
      final byVehicle = await _client
          .from('partner_portal_accounts')
          .select('id')
          .eq('partner_vehicle_id', partnerVehicleId)
          .maybeSingle();
      if (byVehicle != null) {
        await _client.from('partner_portal_accounts').update({
          'partner_id': partnerId,
          'company_id': companyId,
          'username': normalizedUsername,
          'login_email': normalizedEmail,
          'profile_id': profileId,
          if (phone != null) 'phone': phone,
          'is_active': true,
        }).eq('id', byVehicle['id'] as String);
        return;
      }
    }

    await _client.from('partner_portal_accounts').insert({
      'partner_id': partnerId,
      'company_id': companyId,
      'username': normalizedUsername,
      'login_email': normalizedEmail,
      'profile_id': profileId,
      if (partnerVehicleId != null) 'partner_vehicle_id': partnerVehicleId,
      if (phone != null) 'phone': phone,
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
    await ensureCanonicalFleetShifts(companyId);
  }

  /// Erstatter aktive skift med standardlisten (gamle skift arkiveres, PDF-er beholder shift_id).
  static Future<void> ensureCanonicalFleetShifts(String companyId) async {
    if (!_ok) return;
    final active = await fetchFleetShifts(companyId);
    final names = active.map((s) => s.name).toSet();
    final canonical = FleetShiftSeed.canonicalNames.toSet();
    if (names.length == canonical.length && canonical.every(names.contains)) {
      return;
    }
    await replaceAllFleetShiftsWithCanonical(companyId);
  }

  /// Tving inn standard skiftliste (arkiverer alle aktive først).
  static Future<void> replaceAllFleetShiftsWithCanonical(String companyId) async {
    if (!_ok) return;
    await _client
        .from('fleet_shift_definitions')
        .update({'is_archived': true})
        .eq('company_id', companyId)
        .eq('is_archived', false);
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

  static Future<List<FleetShiftDefinition>> fetchArchivedFleetShifts(String companyId) async {
    if (!_ok) return const [];
    final data = await _client
        .from('fleet_shift_definitions')
        .select()
        .eq('company_id', companyId)
        .eq('is_archived', true)
        .order('name') as List<dynamic>;
    return data.map((e) => FleetShiftDefinition.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<List<PartnerRouteShare>> fetchRouteSharesForShift(
    String companyId,
    String shiftId, {
    int limit = 500,
  }) async {
    if (!_ok) return const [];
    final data = await _client
        .from('partner_route_shares')
        .select()
        .eq('company_id', companyId)
        .eq('shift_id', shiftId)
        .order('share_date', ascending: false)
        .limit(limit) as List<dynamic>;
    return data.map((e) => PartnerRouteShare.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> updateFleetShift(
    String shiftId, {
    String? name,
    String? description,
    String? colorHex,
    String? regionGroup,
    String? timeBand,
    String? shiftKind,
  }) async {
    if (!_ok) return;
    final patch = <String, dynamic>{};
    if (name != null) patch['name'] = name;
    if (description != null) patch['description'] = description;
    if (colorHex != null) patch['color_hex'] = colorHex;
    if (regionGroup != null) patch['region_group'] = regionGroup;
    if (timeBand != null) patch['time_band'] = timeBand;
    if (shiftKind != null) patch['shift_kind'] = shiftKind;
    if (patch.isEmpty) return;
    await _client.from('fleet_shift_definitions').update(patch).eq('id', shiftId);
  }

  static Future<void> archiveFleetShift(String shiftId) async {
    if (!_ok) return;
    await _client.from('fleet_shift_definitions').update({'is_archived': true}).eq('id', shiftId);
  }

  static Future<void> unarchiveFleetShift(String shiftId) async {
    if (!_ok) return;
    await _client.from('fleet_shift_definitions').update({'is_archived': false}).eq('id', shiftId);
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
