import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../config/app_origin.dart';
import '../../config/supabase_config.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/vehicle_inspection.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/sap_route_inbox.dart';
import '../../utils/portal_credentials.dart';
import '../sms/sms_phone_utils.dart';
import 'fleet_shift_filters.dart';
import 'fleet_shift_seed.dart';
import 'mavi_unit_codes.dart';
import '../storage/company_file_storage.dart';
import 'postal_code_registry.dart';
import 'route_pdf_text_service.dart';
import 'route_pdf_auto_assign.dart';
import 'route_shift_resolver.dart';

class PartnerService {
  static SupabaseClient get _client => Supabase.instance.client;

  static bool get _ok =>
      !SupabaseConfig.url.startsWith('YOUR_') &&
      !SupabaseConfig.anonKey.startsWith('YOUR_');

  static Future<List<Partner>> fetchPartners({
    required String companyId,
    bool activeOnly = false,
  }) async {
    if (!_ok) return const [];
    var query = _client.from('partners').select().eq('company_id', companyId);
    if (activeOnly) query = query.eq('is_active', true);
    final data = await query.order('name') as List<dynamic>;
    return data.map((e) => Partner.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> setPartnerActive({
    required String partnerId,
    required bool isActive,
  }) async {
    if (!_ok) return;
    await _client.from('partners').update({
      'is_active': isActive,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', partnerId);
  }

  static Future<void> setVehicleActive({
    required String vehicleId,
    required bool isActive,
  }) async {
    if (!_ok) return;
    await _client.from('partner_vehicles').update({
      'is_active': isActive,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', vehicleId);
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

  static Future<void> updatePartnerFields(
    String id,
    Map<String, dynamic> fields,
  ) async {
    if (!_ok || fields.isEmpty) return;
    await _client.from('partners').update(fields).eq('id', id);
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
    final stored = await CompanyFileStorage.upload(
      supabaseBucket: 'documents',
      storagePath: path,
      bytes: bytes,
      category: 'partners',
      fileName: fileName,
    );
    return stored.path;
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

  static Future<PartnerMeeting> addMeeting(PartnerMeeting m, {String? companyId}) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    final row = await _client
        .from('partner_meetings')
        .insert(m.toInsertJson(companyId: companyId))
        .select()
        .single();
    return PartnerMeeting.fromJson(row);
  }

  static Future<void> updateMeeting(String id, PartnerMeeting m) async {
    if (!_ok) return;
    await _client.from('partner_meetings').update(m.toUpdateJson()).eq('id', id);
  }

  static Future<void> completeMeeting(String id) async {
    if (!_ok) return;
    await _client.from('partner_meetings').update({
      'status': 'gjennomfort',
      'completed_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  static Future<void> archiveMeeting(String id) async {
    if (!_ok) return;
    await _client.from('partner_meetings').update({
      'status': 'arkivert',
      'archived_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  static Future<int> sendMeetingSms({
    required String partnerId,
    required String message,
    String? meetingId,
  }) async {
    final n = await notifyMeetingSms(partnerId: partnerId, message: message);
    if (_ok && meetingId != null && n > 0) {
      await _client.from('partner_meetings').update({
        'sms_sent_at': DateTime.now().toIso8601String(),
        'sms_message': message,
      }).eq('id', meetingId);
    }
    return n;
  }

  static Future<List<PartnerTransportLicense>> fetchTransportLicenses(String partnerId) async {
    if (!_ok) return const [];
    try {
      final data = await _client
          .from('partner_transport_licenses')
          .select()
          .eq('partner_id', partnerId)
          .order('valid_to', ascending: true) as List<dynamic>;
      return data.map((e) => PartnerTransportLicense.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<PartnerTransportLicense> addTransportLicense(PartnerTransportLicense lic) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    final row = await _client
        .from('partner_transport_licenses')
        .insert(lic.toInsertJson())
        .select()
        .single();
    final saved = PartnerTransportLicense.fromJson(row);
    await _syncPartnerLicenseCounts(lic.partnerId);
    return saved;
  }

  static Future<void> deleteTransportLicense(String id, String partnerId) async {
    if (!_ok) return;
    await _client.from('partner_transport_licenses').delete().eq('id', id);
    await _syncPartnerLicenseCounts(partnerId);
  }

  static Future<void> _syncPartnerLicenseCounts(String partnerId) async {
    final list = await fetchTransportLicenses(partnerId);
    final partner = await fetchPartner(partnerId);
    if (partner == null) return;
    await updatePartner(
      partnerId,
      Partner(
        id: partner.id,
        companyId: partner.companyId,
        orgNumber: partner.orgNumber,
        name: partner.name,
        tradeName: partner.tradeName,
        ownerName: partner.ownerName,
        phone: partner.phone,
        email: partner.email,
        address: partner.address,
        postalCode: partner.postalCode,
        city: partner.city,
        country: partner.country,
        notes: partner.notes,
        vehicleCountRegistered: partner.vehicleCountRegistered,
        vehicleMaxPayloadKg: partner.vehicleMaxPayloadKg,
        euApproved: partner.euApproved,
        hasTransportLicense: list.isNotEmpty,
        transportLicenseCount: list.length,
        employeeCount: partner.employeeCount,
        auditStatus: partner.auditStatus,
        auditPlate: partner.auditPlate,
        brregSnapshot: partner.brregSnapshot,
        lastMeetingAt: partner.lastMeetingAt,
        nextMeetingAt: partner.nextMeetingAt,
        lastAuditAt: partner.lastAuditAt,
        nextAuditAt: partner.nextAuditAt,
        isActive: partner.isActive,
        routesOwnerOnly: partner.routesOwnerOnly,
        createdAt: partner.createdAt,
      ),
    );
  }

  static Future<String> uploadPartnerDocumentFile({
    required String storagePath,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    final stored = await CompanyFileStorage.upload(
      supabaseBucket: 'documents',
      storagePath: storagePath,
      bytes: bytes,
      category: 'partners',
      fileName: storagePath.split('/').last,
    );
    return stored.path;
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

  /// Flytter kladd (staged) til annen MAVI/partner uten SMS.
  static Future<void> reassignStagedRouteShare({
    required PartnerRouteShare share,
    required String partnerId,
    required String partnerVehicleId,
    String? title,
  }) async {
    if (!_ok) return;
    await updateRouteShareFields(share.id, {
      'partner_id': partnerId,
      'partner_vehicle_id': partnerVehicleId,
      if (title != null) 'title': title,
    });
  }

  /// Flytter en sendt rute-PDF til annen MAVI-bil (oppdaterer partner hvis nødvendig),
  /// nullstiller aksept og oppdaterer flåtesnapshot til valgt dag/skift.
  static Future<void> reassignRouteShareToVehicle({
    required PartnerRouteShare share,
    required FleetPartnerVehicleRow newTarget,
    required DateTime routeDate,
    required String shiftId,
    DateTime? routeStartAt,
  }) async {
    if (!_ok) return;
    final d = routeDate.toIso8601String().split('T').first;
    final oldVid = share.partnerVehicleId;
    final patch = <String, dynamic>{
      'partner_id': newTarget.partner.id,
      'partner_vehicle_id': newTarget.vehicle.id,
      'shift_id': shiftId,
      'share_date': d,
      'ack_status': 'pending',
      'ack_at': null,
      'ack_by': null,
      'ack_comment': null,
    };
    if (routeStartAt != null) {
      patch['route_start_at'] = routeStartAt.toUtc().toIso8601String();
    }
    await updateRouteShareFields(share.id, patch);

    if (oldVid != null && oldVid != newTarget.vehicle.id) {
      await upsertFleetSnapshot(
        PartnerVehicleFleetSnapshot(
          id: '',
          companyId: share.companyId,
          partnerVehicleId: oldVid,
          snapshotDate: DateTime.parse(d),
          shiftId: shiftId,
          status: 'ledig',
          partnerRouteShareId: null,
          notes: 'Rute flyttet',
          createdAt: DateTime.now(),
        ),
      );
    }

    await upsertFleetSnapshot(
      PartnerVehicleFleetSnapshot(
        id: '',
        companyId: share.companyId,
        partnerVehicleId: newTarget.vehicle.id,
        snapshotDate: DateTime.parse(d),
        shiftId: shiftId,
        status: 'har_rute',
        partnerRouteShareId: share.id,
        notes: null,
        createdAt: DateTime.now(),
      ),
    );

    try {
      await _client.rpc('notify_partner_route_assigned_sms', params: {
        'p_route_share_id': share.id,
      });
      await flushSmsOutbox();
    } catch (_) {}
  }

  /// Kalenderdag for en rute — prioriterer planlagt start, ellers share_date.
  static DateTime routeDayForShare(PartnerRouteShare share) {
    final base = share.routeStartAt?.toLocal() ?? share.shareDate;
    return _dayOnly(base);
  }

  /// Grupperer ruter etter kalenderdag (sortert kronologisk).
  static Map<DateTime, List<PartnerRouteShare>> groupSharesByRouteDay(
    List<PartnerRouteShare> shares,
  ) {
    final buckets = <DateTime, List<PartnerRouteShare>>{};
    for (final s in shares) {
      final d = routeDayForShare(s);
      buckets.putIfAbsent(d, () => []).add(s);
    }
    final keys = buckets.keys.toList()..sort();
    return {for (final k in keys) k: buckets[k]!};
  }

  /// Oppdaterer [share_date] og justerer [route_start_at] til samme dag.
  static Future<void> updateShareRouteDay({
    required PartnerRouteShare share,
    required DateTime day,
    int? startHour,
    int? startMinute,
  }) async {
    final dn = _dayOnly(day);
    final h = startHour ?? share.routeStartAt?.toLocal().hour ?? 6;
    final m = startMinute ?? share.routeStartAt?.toLocal().minute ?? 0;
    await updateRouteShareFields(share.id, {
      'share_date': dn.toIso8601String().split('T').first,
      'route_start_at': DateTime(dn.year, dn.month, dn.day, h, m).toUtc().toIso8601String(),
    });
  }

  /// Sletter alle ruter på en dag (kladd + publiserte) og nullstiller snapshots.
  static Future<int> clearRouteSharesForCompanyDay({
    required String companyId,
    required DateTime day,
    bool stagedOnly = false,
  }) async {
    if (!_ok) return 0;
    final dn = _dayOnly(day);
    final shares = await fetchRouteSharesForCalendarWindow(
      companyId: companyId,
      fromDay: dn,
      toDay: dn,
    );
    final targets = stagedOnly ? shares.where((s) => s.isStaged).toList() : shares;
    for (final s in targets) {
      await deleteRouteShare(s);
    }
    return targets.length;
  }

  /// Fjerner rute-PDF fra bil og nullstiller flåtesnapshot.
  static Future<void> deleteRouteShare(PartnerRouteShare share) async {
    if (!_ok) return;
    final d = routeDayForShare(share).toIso8601String().split('T').first;
    final vid = share.partnerVehicleId;
    if (vid != null && share.shiftId != null) {
      await upsertFleetSnapshot(
        PartnerVehicleFleetSnapshot(
          id: '',
          companyId: share.companyId,
          partnerVehicleId: vid,
          snapshotDate: DateTime.parse(d),
          shiftId: share.shiftId!,
          status: 'ledig',
          partnerRouteShareId: null,
          notes: 'Rute fjernet',
          createdAt: DateTime.now(),
        ),
      );
    }
    await _client.from('partner_route_shares').delete().eq('id', share.id);
  }

  /// Varsler sjåfør på nytt om eksisterende sendt rute.
  static Future<bool> notifyRouteShareSms(String shareId) async {
    if (!_ok) return false;
    try {
      await _client.rpc('notify_partner_route_assigned_sms', params: {
        'p_route_share_id': shareId,
      });
      await flushSmsOutbox();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<PartnerPortalAccount>> fetchCompanyPortalAccounts(String companyId) async {
    if (!_ok) return const [];
    try {
      final data = await _client
              .from('partner_portal_accounts')
              .select()
              .eq('company_id', companyId)
              .eq('is_active', true)
              .order('created_at', ascending: false)
          as List<dynamic>;
      return data.map((e) => PartnerPortalAccount.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Send fritekst-SMS til partner/sjåfør (legges i sms_outbox, sendes via Sveve-worker).
  static Future<PartnerSmsQueueResult> queuePartnerComposeSms({
    required String companyId,
    required String phone,
    required String message,
  }) async {
    final normalized = normalizePhoneNo(phone);
    if (!_ok || normalized == null) {
      return const PartnerSmsQueueResult(
        success: false,
        error: 'Ugyldig norsk mobilnummer (8 siffer, starter med 4 eller 9)',
      );
    }
    if (message.trim().isEmpty) {
      return const PartnerSmsQueueResult(success: false, error: 'Meldingen er tom');
    }
    try {
      final result = await _client.rpc('queue_sms', params: {
        'p_company_id': companyId,
        'p_to_phone': normalized,
        'p_message': message.trim(),
        'p_category': 'partner_compose',
        'p_reference_type': 'partners',
        'p_reference_id': null,
        'p_to_user_id': null,
        'p_triggered_by_user_id': null,
      });
      // Eldre queue_sms returnerer void → null selv ved suksess.
      if (result == null) {
        return PartnerSmsQueueResult(success: true, outboxId: null);
      }
      final id = result.toString();
      if (id.isEmpty || id == 'null') {
        return const PartnerSmsQueueResult(
          success: false,
          error: 'Telefonnummer avvist av SMS-kø (ugyldig format)',
        );
      }
      return PartnerSmsQueueResult(success: true, outboxId: id);
    } catch (e) {
      return PartnerSmsQueueResult(success: false, error: e.toString());
    }
  }

  /// Trigger Sveve-worker som sender pending rader i sms_outbox.
  static Future<Map<String, dynamic>?> flushSmsOutbox() async {
    if (!_ok) return null;
    try {
      final res = await _client.functions.invoke('send-sms-outbox');
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return {'processed': 0, 'sent': 0, 'failed': 0};
    } catch (e) {
      return {'error': e.toString(), 'processed': 0, 'sent': 0, 'failed': 0};
    }
  }

  static String? _smsFlushErrorMessage(Map<String, dynamic> flush) {
    final err = flush['error'] as String?;
    if (err != null && err.trim().isNotEmpty) return err.trim();
    final details = flush['details'];
    if (details is List && details.isNotEmpty) {
      final first = details.first;
      if (first is Map) {
        final d = first['error'] as String?;
        if (d != null && d.trim().isNotEmpty) return d.trim();
      }
    }
    final failed = (flush['failed'] as num?)?.toInt() ?? 0;
    if (failed > 0) return 'Sveve avviste $failed SMS — sjekk avsender «Mavi» og saldo';
    return null;
  }

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static Future<List<PartnerRouteShare>> fetchStagedRouteShares(
    String companyId, {
    DateTime? routeDay,
  }) async {
    if (!_ok) return const [];
    try {
      final data = await _client
          .from('partner_route_shares')
          .select()
          .eq('company_id', companyId)
          .eq('dispatch_status', 'staged')
          .order('created_at', ascending: false) as List<dynamic>;
      var list = data.map((e) => PartnerRouteShare.fromJson(e as Map<String, dynamic>)).toList();
      if (routeDay != null) {
        final dn = _dayOnly(routeDay);
        list = list.where((s) {
          final sd = _dayOnly(s.shareDate);
          final rs = s.routeStartAt != null ? _dayOnly(s.routeStartAt!.toLocal()) : null;
          return sd == dn || rs == dn;
        }).toList();
      }
      return list;
    } catch (_) {
      final all = await fetchRouteSharesForCompany(companyId, limit: 500);
      var list = all.where((s) => s.shiftId == null && s.ackStatus == 'pending').toList();
      if (routeDay != null) {
        final dn = _dayOnly(routeDay);
        list = list.where((s) {
          final sd = _dayOnly(s.shareDate);
          return sd == dn;
        }).toList();
      }
      return list;
    }
  }

  static Future<int> countStagedRouteShares(
    String companyId, {
    DateTime? routeDay,
  }) async {
    final list = await fetchStagedRouteShares(companyId, routeDay: routeDay);
    return list.length;
  }

  /// Send staged ruter — hver rute kan ha eget skift og starttid.
  static Future<void> dispatchRouteShares({
    required String companyId,
    required Map<String, String> shareIdToShiftId,
    required DateTime date,
    Map<String, DateTime?> shareIdToStartAt = const {},
    bool notifyDriver = true,
  }) async {
    if (!_ok || shareIdToShiftId.isEmpty) return;

    final status = notifyDriver ? 'sent' : 'registered';

    for (final entry in shareIdToShiftId.entries) {
      final startAt = shareIdToStartAt[entry.key];
      final routeDay = startAt != null
          ? DateTime(startAt.year, startAt.month, startAt.day)
          : date;
      final d = routeDay.toIso8601String().split('T').first;
      final patch = <String, dynamic>{
        'dispatch_status': status,
        'shift_id': entry.value,
        'share_date': d,
      };
      if (startAt != null) {
        patch['route_start_at'] = startAt.toUtc().toIso8601String();
      }
      await _client.from('partner_route_shares').update(patch).eq('id', entry.key);

      final row = await _client
          .from('partner_route_shares')
          .select('partner_vehicle_id, pdf_search_text')
          .eq('id', entry.key)
          .maybeSingle();
      final pdfText = row?['pdf_search_text'] as String?;
      if (pdfText != null && pdfText.trim().isNotEmpty) {
        final n = RoutePdfTextService.parseCustomers(pdfText).length;
        if (n > 0) {
          await _client.from('partner_route_shares').update({'customer_count': n}).eq('id', entry.key);
        }
      }
      final vid = row?['partner_vehicle_id'] as String?;
      if (vid == null) continue;

      await upsertFleetSnapshot(
        PartnerVehicleFleetSnapshot(
          id: '',
          companyId: companyId,
          partnerVehicleId: vid,
          snapshotDate: routeDay,
          shiftId: entry.value,
          status: 'har_rute',
          partnerRouteShareId: entry.key,
          notes: startAt != null
              ? 'Start ${startAt.hour.toString().padLeft(2, '0')}:${startAt.minute.toString().padLeft(2, '0')}'
              : null,
          createdAt: DateTime.now(),
        ),
      );

      // SMS sendes kun når dispatch_status = sent (trg_partner_route_sms_on_sent).
    }
    if (notifyDriver) {
      try {
        await flushSmsOutbox();
      } catch (_) {}
    }
  }

  /// Publiser alle ruter i kladd ([dispatchStatus] = staged) til sjåfører.
  /// Bruker [defaultShiftId], eller første ruteskift; for hver rad brukes egen `shift_id` om den allerede er satt.
  static Future<int> dispatchAllStagedRouteShares({
    required String companyId,
    required DateTime routeDate,
    String? defaultShiftId,
    int defaultStartHour = 6,
    int defaultStartMinute = 0,
  }) async {
    if (!_ok) return 0;
    final staged = await fetchStagedRouteShares(companyId);
    if (staged.isEmpty) return 0;
    final shifts = await fetchFleetShifts(companyId);
    final routeOps = shifts.where((s) => !s.isAvailability && s.shiftKind == 'route_ops').toList();
    final selectable = routeOps.isNotEmpty ? routeOps : shifts.where((s) => !s.isAvailability).toList();
    final fallbackShift = defaultShiftId ?? (selectable.isNotEmpty ? selectable.first.id : null);
    if (fallbackShift == null) return 0;

    final map = <String, String>{};
    final starts = <String, DateTime?>{};

    for (final s in staged) {
      final day = routeDayForShare(s);
      map[s.id] = s.shiftId ?? fallbackShift;
      starts[s.id] = s.routeStartAt ??
          DateTime(
            day.year,
            day.month,
            day.day,
            defaultStartHour,
            defaultStartMinute,
          );
    }

    await dispatchRouteShares(
      companyId: companyId,
      shareIdToShiftId: map,
      date: staged.isNotEmpty ? routeDayForShare(staged.first) : routeDate,
      shareIdToStartAt: starts,
    );
    return staged.length;
  }

  static String suggestedPortalLoginEmail({
    required String partnerId,
    required bool isOwner,
    String? partnerVehicleId,
  }) {
    return PortalCredentials.loginEmail(
      partnerId: partnerId,
      isOwner: isOwner,
      partnerVehicleId: partnerVehicleId,
    );
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
    String? driverName,
    bool regeneratePassword = false,
  }) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    final username = PortalCredentials.driverUsername(unitCode);
    final password = PortalCredentials.generatePassword();
    final loginEmail = PortalCredentials.loginEmail(
      partnerId: partnerId,
      isOwner: false,
      partnerVehicleId: partnerVehicleId,
    );
    final res = await _invokePortalProvision(
      partnerId: partnerId,
      companyId: companyId,
      partnerVehicleId: partnerVehicleId,
      username: username,
      loginEmail: loginEmail,
      phone: phone,
      password: password,
      driverName: driverName,
      accountKind: 'driver',
      sendCredentialsSms: true,
      regeneratePassword: regeneratePassword,
    );
    return res;
  }

  static Future<List<PartnerDocument>> fetchOwnerPortalDocuments(String partnerId) async {
    final all = await fetchDocuments(partnerId);
    return all.where((d) => d.ownerVisible).toList();
  }

  static Future<List<PartnerDocument>> fetchDriverPortalDocuments(String partnerId) async {
    final all = await fetchDocuments(partnerId);
    return all.where((d) => d.driverVisible).toList();
  }

  static Future<List<PartnerMeeting>> fetchPortalMeetings(String partnerId) async {
    return fetchMeetings(partnerId);
  }

  /// Genererer nytt passord og sender på SMS til eksisterende bil-eier-portal.
  static Future<PortalProvisionResult> resendOwnerPortalPassword({
    required String partnerId,
    required String companyId,
    required String phone,
    required String partnerName,
    String? orgNumber,
  }) {
    return provisionOwnerPortal(
      partnerId: partnerId,
      companyId: companyId,
      phone: phone,
      partnerName: partnerName,
      orgNumber: orgNumber,
      regeneratePassword: true,
    );
  }

  /// Genererer nytt passord og sender på SMS til eksisterende sjåfør-portal.
  static Future<PortalProvisionResult> resendDriverPortalPassword({
    required String partnerId,
    required String companyId,
    required String partnerVehicleId,
    required String unitCode,
    required String phone,
    String? driverName,
  }) {
    return provisionDriverPortal(
      partnerId: partnerId,
      companyId: companyId,
      partnerVehicleId: partnerVehicleId,
      unitCode: unitCode,
      phone: phone,
      driverName: driverName,
      regeneratePassword: true,
    );
  }

  static Future<PortalProvisionResult> provisionOwnerPortal({
    required String partnerId,
    required String companyId,
    required String phone,
    required String partnerName,
    String? orgNumber,
    bool regeneratePassword = false,
  }) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    final username = PortalCredentials.ownerUsername(
      partnerName: partnerName,
      orgNumber: orgNumber,
      partnerId: partnerId,
    );
    final password = PortalCredentials.generatePassword();
    final loginEmail = PortalCredentials.loginEmail(
      partnerId: partnerId,
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
    String? driverName,
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
        'phone': normalizePhoneNo(phone.trim()) ?? phone.trim(),
        'password': password,
        if (driverName != null && driverName.trim().isNotEmpty) 'driver_name': driverName.trim(),
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
      var smsSent = data['sms_sent'] == true;
      final smsQueued = data['sms_queued'] == true;
      var smsError = data['sms_error'] as String?;
      if (!smsSent) {
        final flush = await flushSmsOutbox();
        if (flush != null) {
          final sent = (flush['sent'] as num?)?.toInt() ?? 0;
          if (sent > 0) {
            smsSent = true;
            smsError = null;
          } else {
            smsError ??= _smsFlushErrorMessage(flush);
          }
        }
      }
      return PortalProvisionResult(
        username: (data['username'] as String?) ?? username,
        loginEmail: (data['login_email'] as String?) ?? loginEmail,
        password: (data['password'] as String?) ?? password,
        smsSent: smsSent,
        smsQueued: smsQueued,
        smsError: smsError,
        phone: data['phone'] as String?,
      );
    }
    return PortalProvisionResult(
      username: username,
      loginEmail: loginEmail,
      password: password,
    );
  }

  /// Hvilken portal (bil-eier vs sjåfør) innlogget bruker skal ha.
  static Future<PartnerPortalSession?> resolvePortalSession() async {
    if (!_ok) return null;
    try {
      final raw = await _client.rpc('resolve_partner_portal_bootstrap');
      if (raw is Map) {
        return PartnerPortalSession.fromJson(Map<String, dynamic>.from(raw));
      }
    } catch (_) {}

    final uid = _client.auth.currentUser?.id;
    final email = _client.auth.currentUser?.email?.trim().toLowerCase();
    if (uid != null) {
      try {
        final row = await _client
            .from('partner_portal_accounts')
            .select()
            .eq('is_active', true)
            .eq('profile_id', uid)
            .maybeSingle();
        if (row != null) {
          return PartnerPortalSession.fromAccount(row as Map<String, dynamic>);
        }
      } catch (_) {}
    }
    if (email != null && email.isNotEmpty) {
      try {
        final row = await _client
            .from('partner_portal_accounts')
            .select()
            .eq('is_active', true)
            .eq('login_email', email)
            .maybeSingle();
        if (row != null) {
          return PartnerPortalSession.fromAccount(row as Map<String, dynamic>);
        }
      } catch (_) {}
    }
    return null;
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
    DateTime? requestDateFrom,
    DateTime? requestDateTo,
  }) async {
    if (!_ok) return const [];
    try {
      var q = _client.from('partner_fri_requests').select();
      if (companyId != null) q = q.eq('company_id', companyId);
      if (partnerId != null) q = q.eq('partner_id', partnerId);
      if (status != null) q = q.eq('status', status);
      if (requestDateFrom != null) {
        q = q.gte('request_date', requestDateFrom.toIso8601String().split('T').first);
      }
      if (requestDateTo != null) {
        q = q.lte('request_date', requestDateTo.toIso8601String().split('T').first);
      }
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

  static Future<List<PartnerVehicle>> fetchVehicles(
    String partnerId, {
    bool activeOnly = false,
  }) async {
    if (!_ok) return const [];
    var query = _client.from('partner_vehicles').select().eq('partner_id', partnerId);
    if (activeOnly) query = query.eq('is_active', true);
    final data = await query.order('unit_code', ascending: true) as List<dynamic>;
    return data.map((e) => PartnerVehicle.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<List<PartnerVehicle>> replaceVehicles({
    required String partnerId,
    required String companyId,
    required List<PartnerVehicle> vehicles,
  }) async {
    if (!_ok) {
      throw StateError('Supabase er ikke konfigurert');
    }
    final existing = await fetchVehicles(partnerId);
    final keepUnits = vehicles.map((v) => v.unitCode.toUpperCase()).toSet();

    for (final old in existing) {
      if (!keepUnits.contains(old.unitCode.toUpperCase())) {
        await _client.from('partner_vehicles').delete().eq('id', old.id);
      }
    }

    for (final v in vehicles) {
      final json = v.toUpsertJson()..remove('id');
      if (v.id.isNotEmpty) {
        await _client.from('partner_vehicles').update(json).eq('id', v.id);
      } else {
        await _client.from('partner_vehicles').insert(json);
      }
    }
    return fetchVehicles(partnerId);
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
    if (input.isEmpty) return null;
    if (input.contains('@')) return input.toLowerCase();
    if (!_ok) {
      throw StateError('Appen er ikke koblet til Supabase. Kontakt administrator.');
    }
    final val = await _client.rpc('resolve_partner_login_email', params: {
      'p_username': input.toLowerCase(),
    });
    if (val is String && val.trim().isNotEmpty) return val.trim().toLowerCase();
    return null;
  }

  /// Glemt passord: nytt passord i Supabase Auth + SMS til registrert telefon.
  static Future<PartnerPortalPasswordResetResult> resetPortalPasswordByUsername(
    String username,
  ) async {
    if (!_ok) {
      return const PartnerPortalPasswordResetResult(
        success: false,
        error: 'Appen er ikke koblet til Supabase.',
      );
    }
    final u = username.trim().toLowerCase();
    if (u.length < 2) {
      return const PartnerPortalPasswordResetResult(
        success: false,
        error: 'Skriv brukernavnet ditt.',
      );
    }
    try {
      final res = await _client.functions.invoke(
        'partner-portal-reset-password',
        body: {'username': u},
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        if (data['error'] != null) {
          return PartnerPortalPasswordResetResult(
            success: false,
            error: data['error'].toString(),
          );
        }
        return PartnerPortalPasswordResetResult(
          success: data['ok'] == true,
          message: data['message'] as String? ??
              'Nytt passord er sendt på SMS.',
        );
      }
      return const PartnerPortalPasswordResetResult(
        success: false,
        error: 'Uventet svar fra server.',
      );
    } catch (e) {
      return PartnerPortalPasswordResetResult(success: false, error: e.toString());
    }
  }

  /// Laster opp rute-PDF. Returnerer faktisk lagringssti (Supabase eller Dropbox).
  static Future<String> uploadPartnerRoutePdf({
    required String storagePath,
    required Uint8List bytes,
  }) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    final result = await CompanyFileStorage.upload(
      supabaseBucket: 'documents',
      storagePath: storagePath,
      bytes: bytes,
      category: 'routes',
      fileName: storagePath.split('/').last,
    );
    return result.path;
  }

  static Future<String> getRoutePdfSignedUrl(String storagePath) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    final raw = storagePath.trim();
    if (raw.isEmpty) throw ArgumentError('PDF-sti mangler');
    if (CompanyFileStorage.isDropboxPath(raw)) {
      return CompanyFileStorage.getDropboxTemporaryLink(raw);
    }
    final path = raw.replaceFirst(RegExp(r'^/'), '');
    return _client.storage.from('documents').createSignedUrl(path, 3600);
  }

  /// Leser kunder (navn + telefon) fra rute-PDF for sjåfør på valgt dag.
  static Future<List<RoutePdfCustomer>> fetchRouteCustomersForVehicleDay({
    required String companyId,
    required String partnerVehicleId,
    required DateTime day,
  }) async {
    if (!_ok) return const [];
    final d = DateTime(day.year, day.month, day.day);
    final routes = await fetchRouteSharesForCompany(
      companyId,
      shareDateFrom: d,
      shareDateTo: d,
    );
    final forVehicle = routes
        .where(
          (r) =>
              r.partnerVehicleId == partnerVehicleId &&
              r.dispatchStatus == 'sent' &&
              r.pdfStoragePath.trim().isNotEmpty,
        )
        .toList();
    if (forVehicle.isEmpty) return const [];

    final merged = <RoutePdfCustomer>[];
    final seenPhones = <String>{};

    for (final route in forVehicle) {
      var parsed = <RoutePdfCustomer>[];
      final cached = route.pdfSearchText?.trim();
      if (cached != null && cached.isNotEmpty) {
        parsed = RoutePdfTextService.parseCustomers(cached);
      } else {
        try {
          final url = await getRoutePdfSignedUrl(route.pdfStoragePath);
          final res = await http.get(Uri.parse(url));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            parsed = RoutePdfTextService.parseCustomersFromBytes(res.bodyBytes);
          }
        } catch (_) {
          parsed = const [];
        }
      }
      for (final c in parsed) {
        if (seenPhones.add(c.phoneNormalizedKey)) {
          merged.add(c);
        }
      }
    }

    merged.sort((a, b) => a.sequence.compareTo(b.sequence));
    return merged;
  }

  static Future<String> uploadPartnerDocumentPdf({
    required String storagePath,
    required Uint8List bytes,
  }) async {
    return uploadPartnerRoutePdf(storagePath: storagePath, bytes: bytes);
  }

  static Future<String> getDocumentPdfSignedUrl(String storagePath) async {
    return getRoutePdfSignedUrl(storagePath);
  }

  /// Visnings-URL for lagret filsti (Supabase eller Dropbox).
  static Future<String> resolveStorageUrl(String storagePathOrUrl) async {
    if (CompanyFileStorage.isDropboxReference(storagePathOrUrl)) {
      return CompanyFileStorage.resolveDisplayUrl(storagePathOrUrl);
    }
    final raw = storagePathOrUrl.trim().replaceFirst(RegExp(r'^/'), '');
    if (raw.isEmpty) throw ArgumentError('Sti mangler');
    return _client.storage.from('documents').createSignedUrl(raw, 3600);
  }

  // ── Flåte / skift / sporingsdashboard ─────────────────────────────────

  static Future<void> ensureDefaultFleetShifts(String companyId) async {
    await ensureCanonicalFleetShifts(companyId);
  }

  /// Erstatter aktive skift med standardlisten (gamle skift arkiveres, PDF-er beholder shift_id).
  static Future<void> ensureCanonicalFleetShifts(String companyId) async {
    if (!_ok) return;
    await _archiveGeiloFleetShifts(companyId);
    final active = await fetchFleetShifts(companyId);
    if (active.isNotEmpty &&
        FleetShiftSeed.matchesCatalog(active.map((s) => s.name).toList())) {
      return;
    }
    await replaceAllFleetShiftsWithCanonical(companyId);
    await _archiveGeiloFleetShifts(companyId);
  }

  static Future<void> _archiveGeiloFleetShifts(String companyId) async {
    final active = await fetchFleetShifts(companyId);
    for (final s in active) {
      if (FleetShiftFilters.isGeilo(s)) {
        await archiveFleetShift(s.id);
      }
    }
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

  static Future<List<FleetPartnerVehicleRow>> fetchCompanyFleet(
    String companyId, {
    bool forPlanning = true,
  }) async {
    if (!_ok) return const [];
    final partners = await fetchPartners(companyId: companyId, activeOnly: forPlanning);
    final out = <FleetPartnerVehicleRow>[];
    for (final p in partners) {
      if (forPlanning && !p.isActive) continue;
      for (final v in await fetchVehicles(p.id, activeOnly: forPlanning)) {
        if (forPlanning && !v.isActive) continue;
        out.add(FleetPartnerVehicleRow(partner: p, vehicle: v));
      }
    }
    return out;
  }

  /// Ruteplanlegging bruker kun MAVI-er — ikke rene reg.nr-rader (REG-AB12345).
  static bool isMaviFleetVehicle(PartnerVehicle vehicle) {
    return vehicle.vehicleKind != 'registration' &&
        !MaviUnitCodes.isRegistrationOnlyUnit(vehicle.unitCode);
  }

  static List<FleetPartnerVehicleRow> filterMaviFleetOnly(
    Iterable<FleetPartnerVehicleRow> rows,
  ) {
    return rows.where((r) => isMaviFleetVehicle(r.vehicle)).toList();
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
    DateTime? shareDateFrom,
    DateTime? shareDateTo,
    int limit = 800,
  }) async {
    if (!_ok) return const [];
    var q =
        _client.from('partner_route_shares').select().eq('company_id', companyId);
    if (shareDateFrom != null) {
      q = q.gte('share_date', shareDateFrom.toIso8601String().split('T').first);
    }
    if (shareDateTo != null) {
      q = q.lte('share_date', shareDateTo.toIso8601String().split('T').first);
    }
    final data =
        await q.order('created_at', ascending: false).limit(limit) as List<dynamic>;
    return data.map((e) => PartnerRouteShare.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Ruter der [route_start_at] eller [share_date] treffer vinduet (kalenderuket).
  static Future<List<PartnerRouteShare>> fetchRouteSharesForCalendarWindow({
    required String companyId,
    required DateTime fromDay,
    required DateTime toDay,
    int limitPerQuery = 2000,
  }) async {
    if (!_ok) return const [];
    final dFrom = DateTime(fromDay.year, fromDay.month, fromDay.day);
    final dTo = DateTime(toDay.year, toDay.month, toDay.day);
    final sd = dFrom.toIso8601String().split('T').first;
    final ed = dTo.toIso8601String().split('T').first;
    final fromTs = DateTime(dFrom.year, dFrom.month, dFrom.day).toUtc().toIso8601String();
    final toTsExclusive =
        DateTime(dTo.year, dTo.month, dTo.day).add(const Duration(days: 1)).toUtc().toIso8601String();

    final byShareDate = await _client
            .from('partner_route_shares')
            .select()
            .eq('company_id', companyId)
            .gte('share_date', sd)
            .lte('share_date', ed)
            .order('created_at', ascending: false)
            .limit(limitPerQuery)
        as List<dynamic>;

    List<dynamic> byStartAt = const [];
    try {
      byStartAt = await _client
              .from('partner_route_shares')
              .select()
              .eq('company_id', companyId)
              .gte('route_start_at', fromTs)
              .lt('route_start_at', toTsExclusive)
              .order('created_at', ascending: false)
              .limit(limitPerQuery)
          as List<dynamic>;
    } catch (_) {
      byStartAt = const [];
    }

    final map = <String, PartnerRouteShare>{};
    for (final e in [...byShareDate, ...byStartAt]) {
      final m = Map<String, dynamic>.from(e as Map);
      final s = PartnerRouteShare.fromJson(m);
      map[s.id] = s;
    }
    return map.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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

  // ── Bilkontroll ─────────────────────────────────────────────────────────

  static Future<List<PartnerVehicleInspection>> fetchVehicleInspections(String partnerId) async {
    if (!_ok) return const [];
    try {
      final data = await _client
          .from('partner_vehicle_inspections')
          .select()
          .eq('partner_id', partnerId)
          .order('inspected_at', ascending: false) as List<dynamic>;
      return data
          .map((e) => PartnerVehicleInspection.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<PartnerVehicleInspection>> fetchOpenInspectionFollowUps({
    required String companyId,
    String? assigneeProfileId,
  }) async {
    if (!_ok) return const [];
    try {
      var q = _client
          .from('partner_vehicle_inspections')
          .select()
          .eq('company_id', companyId)
          .eq('has_deviation', true);
      if (assigneeProfileId != null) {
        q = q.eq('deviation_assignee', assigneeProfileId);
      }
      final data = await q.order('follow_up_due_at', ascending: true) as List<dynamic>;
      return data
          .map((e) => PartnerVehicleInspection.fromJson(e as Map<String, dynamic>))
          .where((i) => i.followUpOpen)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<PartnerVehicleInspection> saveVehicleInspection(
    PartnerVehicleInspection draft,
  ) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('Ikke innlogget');
    final row = await _client
        .from('partner_vehicle_inspections')
        .insert(draft.toInsertJson(inspectedBy: uid))
        .select()
        .single();
    return PartnerVehicleInspection.fromJson(row);
  }

  static Future<void> acknowledgeInspectionFollowUp(String inspectionId) async {
    if (!_ok) return;
    await _client.from('partner_vehicle_inspections').update({
      'follow_up_acknowledged_at': DateTime.now().toIso8601String(),
    }).eq('id', inspectionId);
  }

  // --- SAP rute-innboks (Resend Inbound) ---

  /// Prefiks på [reject_reason] for PDF som ligger i «Manuell»-fanen (ikke «nye»).
  static const String sapInboxManualReasonPrefix = 'MANUAL:';

  static Future<int> countSapRouteInboxPending(String companyId) async {
    if (!_ok) return 0;
    try {
      final data = await _client
          .from('sap_route_inbox')
          .select('id')
          .eq('company_id', companyId)
          .eq('status', 'pending');
      return (data as List).length;
    } catch (_) {
      return 0;
    }
  }

  /// Flytter feilet auto-import ut av «nye PDF»-telleren.
  static Future<void> markSapRouteInboxManual({
    required String id,
    required String reason,
  }) async {
    if (!_ok) return;
    await _client.from('sap_route_inbox').update({
      'status': 'rejected',
      'reject_reason': '$sapInboxManualReasonPrefix$reason',
      'processed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  static Future<List<SapRouteInboxItem>> fetchSapRouteInboxManual(
    String companyId,
  ) async {
    if (!_ok) return const [];
    try {
      final data = await _client
          .from('sap_route_inbox')
          .select()
          .eq('company_id', companyId)
          .eq('status', 'rejected')
          .like('reject_reason', '$sapInboxManualReasonPrefix%')
          .order('received_at', ascending: false) as List<dynamic>;
      return data
          .map((e) => SapRouteInboxItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Pending som allerede finnes som kladd — marker importert (unngår «26 nye» + duplikat).
  static Future<int> reconcileSapInboxWithStagedQueue(String companyId) async {
    if (!_ok) return 0;
    final pending = await fetchSapRouteInboxPending(companyId);
    if (pending.isEmpty) return 0;
    final staged = await fetchStagedRouteShares(companyId);
    if (staged.isEmpty) return 0;

    final stagedPaths = staged.map((s) => s.pdfStoragePath).toSet();
    var reconciled = 0;
    for (final item in pending) {
      PartnerRouteShare? match;
      for (final s in staged) {
        if (s.pdfStoragePath == item.pdfStoragePath) {
          match = s;
          break;
        }
        final title = s.title ?? '';
        if (title.contains(item.fileName)) {
          match = s;
          break;
        }
      }
      if (match == null) continue;
      await markSapRouteInboxImported(
        inboxId: item.id,
        routeShareId: match.id,
        detectedMaviCode: item.detectedMaviCode,
      );
      reconciled++;
    }
    return reconciled;
  }

  static Future<List<SapRouteInboxItem>> fetchSapRouteInboxPending(
    String companyId,
  ) async {
    if (!_ok) return const [];
    try {
      final data = await _client
          .from('sap_route_inbox')
          .select()
          .eq('company_id', companyId)
          .eq('status', 'pending')
          .order('received_at', ascending: false) as List<dynamic>;
      return data
          .map((e) => SapRouteInboxItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> dismissSapRouteInbox(String inboxId) async {
    if (!_ok) return;
    await _client.from('sap_route_inbox').update({
      'status': 'rejected',
      'reject_reason': 'Avvist manuelt',
      'processed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', inboxId);
  }

  static Future<void> markSapRouteInboxRejected({
    required String id,
    required String reason,
  }) async {
    if (!_ok) return;
    await _client.from('sap_route_inbox').update({
      'status': 'rejected',
      'reject_reason': reason,
      'processed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  static Future<void> markSapRouteInboxImported({
    required String inboxId,
    required String routeShareId,
    String? detectedMaviCode,
  }) async {
    if (!_ok) return;
    final uid = _client.auth.currentUser?.id;
    await _client.from('sap_route_inbox').update({
      'status': 'imported',
      'imported_route_share_id': routeShareId,
      if (detectedMaviCode != null) 'detected_mavi_code': detectedMaviCode,
      'processed_at': DateTime.now().toUtc().toIso8601String(),
      if (uid != null) 'processed_by': uid,
    }).eq('id', inboxId);
  }

  static Future<Uint8List?> downloadRoutePdfBytes(String storagePath) async {
    if (!_ok) return null;
    try {
      final url = await getRoutePdfSignedUrl(storagePath);
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        return res.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  /// Oppretter staged rute fra PDF (AUTO MASS / SAP).
  static Future<String> createStagedRouteShareFromPdf({
    required String companyId,
    required Partner partner,
    required PartnerVehicle vehicle,
    required String fileName,
    required Uint8List bytes,
    required DateTime routeDate,
    String? notes,
    RoutePdfParseBundle? parsed,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path =
        'company_$companyId/partner_routes/${DateTime.now().millisecondsSinceEpoch}_${vehicle.unitCode}_$safeName';
    final storedPath =
        await uploadPartnerRoutePdf(storagePath: path, bytes: bytes);
    await PostalCodeRegistry.ensureLoaded();
    await ensureCanonicalFleetShifts(companyId);
    final shifts = await fetchFleetShifts(companyId);
    final bundle = parsed ?? RoutePdfTextService.parseBundle(bytes, fallbackDate: routeDate);
    final routeShifts = FleetShiftFilters.forRouteAssignment(shifts);
    final auto = await RoutePdfAutoAssign.analyze(
      bytes: bytes,
      fallbackDate: routeDate,
      shifts: routeShifts,
      vehicle: vehicle,
      bundle: bundle,
    );
    final pdfText = bundle.searchText;
    final meta = bundle.meta;
    final schedule = bundle.schedule;
    final composedNotes = RoutePdfTextService.composeRouteNotes(
      stowingLane: meta.stowingLane,
      userNote: RoutePdfAutoAssign.composeAutoNotes(auto, existing: notes),
    );
    final share = await addRouteShare(
      PartnerRouteShare(
        id: '',
        partnerId: partner.id,
        companyId: companyId,
        title: 'Rute ${MaviUnitCodes.normalize(vehicle.unitCode)} — $fileName',
        pdfStoragePath: storedPath,
        shareDate: schedule.routeDate,
        isDailyShare: true,
        createdAt: DateTime.now(),
        dispatchStatus: 'staged',
        pdfSearchText: pdfText.isEmpty ? null : pdfText,
        partnerVehicleId: vehicle.id,
        notes: composedNotes.isEmpty ? null : composedNotes,
      ),
    );
    if (pdfText.isNotEmpty) {
      await saveRoutePdfSearchText(share.id, pdfText);
    }
    final patch = <String, dynamic>{};
    if (schedule.routeStartAt != null) {
      patch['route_start_at'] = schedule.routeStartAt!.toUtc().toIso8601String();
    }
    if (auto.shift != null) {
      patch['shift_id'] = auto.shift!.id;
    }
    if (patch.isNotEmpty) {
      await updateRouteShareFields(share.id, patch);
    }
    return share.id;
  }
}

class PartnerSmsQueueResult {
  final bool success;
  final String? error;
  final String? outboxId;

  const PartnerSmsQueueResult({
    required this.success,
    this.error,
    this.outboxId,
  });
}

/// Én linje i flåteoversikten (partner + kjøretøy).
class FleetPartnerVehicleRow {
  final Partner partner;
  final PartnerVehicle vehicle;
  const FleetPartnerVehicleRow({required this.partner, required this.vehicle});
}
