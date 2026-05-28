import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/partner/partner_links.dart';
import '../../../models/partner/vehicle_rental.dart';
import '../storage/company_file_storage.dart';
import '../supabase_service.dart';
import 'partner_service.dart';

class VehicleRentalService {
  VehicleRentalService._();

  static SupabaseClient get _client => Supabase.instance.client;
  static bool get _ok => SupabaseService.isConfigured;

  static const activeStatuses = [
    'pending_owner',
    'pending_mavi',
    'approved',
    'pending_return_mavi',
  ];

  static Future<List<VehicleRental>> fetchForCompany(
    String companyId, {
    String? query,
    String? statusFilter,
  }) async {
    if (!_ok) return const [];
    var q = _client.from('vehicle_rentals').select().eq('company_id', companyId);
    if (statusFilter != null && statusFilter.isNotEmpty) {
      q = q.eq('status', statusFilter);
    }
    final data = await q.order('created_at', ascending: false).limit(500) as List<dynamic>;
    var list = await _attachPartnerNames(
      data.map((e) => VehicleRental.fromJson(e as Map<String, dynamic>)).toList(),
    );
    if (query != null && query.trim().isNotEmpty) {
      final qLower = query.trim().toLowerCase();
      list = list.where((r) {
        return (r.registrationNumber ?? '').toLowerCase().contains(qLower) ||
            (r.unitCode ?? '').toLowerCase().contains(qLower) ||
            (r.vehicleMake ?? '').toLowerCase().contains(qLower) ||
            (r.lenderPartnerName ?? '').toLowerCase().contains(qLower) ||
            (r.borrowerPartnerName ?? '').toLowerCase().contains(qLower);
      }).toList();
    }
    return list;
  }

  static String? vehicleMakeFrom(PartnerVehicle vehicle) {
    final snap = vehicle.vegvesenSnapshot;
    if (snap == null) return null;
    for (final key in ['make', 'merke', 'brand', 'merkenavn']) {
      final v = snap[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  static Future<List<VehicleRental>> fetchForLenderPartner(String partnerId) async {
    if (!_ok) return const [];
    final data = await _client
            .from('vehicle_rentals')
            .select()
            .eq('lender_partner_id', partnerId)
            .order('created_at', ascending: false)
            .limit(200)
        as List<dynamic>;
    return _attachPartnerNames(
      data.map((e) => VehicleRental.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  static Future<List<VehicleRental>> fetchForBorrowerPartner(String partnerId) async {
    if (!_ok) return const [];
    final data = await _client
            .from('vehicle_rentals')
            .select()
            .eq('borrower_partner_id', partnerId)
            .inFilter('status', ['approved', 'pending_return_mavi', 'returned'])
            .order('approved_at', ascending: false)
            .limit(100)
        as List<dynamic>;
    return _attachPartnerNames(
      data.map((e) => VehicleRental.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  /// Kjøretøy med aktiv utleie (kan ikke lånes ut på nytt).
  static Future<Set<String>> fetchBlockedVehicleIds(String companyId) async {
    if (!_ok) return {};
    final data = await _client
            .from('vehicle_rentals')
            .select('partner_vehicle_id')
            .eq('company_id', companyId)
            .inFilter('status', activeStatuses)
        as List<dynamic>;
    return {
      for (final row in data)
        if ((row as Map)['partner_vehicle_id'] != null)
          (row)['partner_vehicle_id'] as String,
    };
  }

  static Future<VehicleRental?> fetchActiveForBorrowerReg({
    required String partnerId,
    required String registrationNumber,
  }) async {
    if (!_ok) return null;
    final reg = registrationNumber.trim().toLowerCase();
    if (reg.isEmpty) return null;
    final list = await fetchForBorrowerPartner(partnerId);
    for (final r in list) {
      if (r.isBlockedOnLoan &&
          (r.registrationNumber ?? '').trim().toLowerCase() == reg) {
        return r;
      }
    }
    return null;
  }

  static Future<VehicleRental?> fetchById(String id) async {
    if (!_ok) return null;
    final row = await _client.from('vehicle_rentals').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    final list = await _attachPartnerNames([VehicleRental.fromJson(row)]);
    return list.isEmpty ? null : list.first;
  }

  static Future<List<VehicleRental>> _attachPartnerNames(List<VehicleRental> rentals) async {
    if (rentals.isEmpty) return rentals;
    final ids = <String>{
      ...rentals.map((r) => r.lenderPartnerId),
      ...rentals.map((r) => r.borrowerPartnerId),
    };
    final partners =
        await _client.from('partners').select('id, name, org_number').inFilter('id', ids.toList());
    final names = <String, String>{
      for (final p in partners as List<dynamic>)
        (p as Map)['id'] as String: (p)['name'] as String,
    };
    final orgNumbers = <String, String?>{
      for (final p in partners as List<dynamic>)
        (p as Map)['id'] as String: (p)['org_number'] as String?,
    };
    return rentals
        .map(
          (r) => VehicleRental(
            id: r.id,
            companyId: r.companyId,
            lenderPartnerId: r.lenderPartnerId,
            borrowerPartnerId: r.borrowerPartnerId,
            partnerVehicleId: r.partnerVehicleId,
            registrationNumber: r.registrationNumber,
            vehicleMake: r.vehicleMake,
            unitCode: r.unitCode,
            rentalStart: r.rentalStart,
            rentalEnd: r.rentalEnd,
            rentalStartAt: r.rentalStartAt,
            rentalEndAt: r.rentalEndAt,
            status: r.status,
            agreementAcceptedAt: r.agreementAcceptedAt,
            ownerSubmittedAt: r.ownerSubmittedAt,
            approvedAt: r.approvedAt,
            approvedBy: r.approvedBy,
            rejectedAt: r.rejectedAt,
            rejectionReason: r.rejectionReason,
            maviCheckoutComment: r.maviCheckoutComment,
            maviReturnComment: r.maviReturnComment,
            fuelLevel: r.fuelLevel,
            odometerKm: r.odometerKm,
            ownerComment: r.ownerComment,
            photos: r.photos,
            returnPhotos: r.returnPhotos,
            returnFuelLevel: r.returnFuelLevel,
            returnOdometerKm: r.returnOdometerKm,
            returnComment: r.returnComment,
            returnSubmittedAt: r.returnSubmittedAt,
            returnApprovedAt: r.returnApprovedAt,
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
            lenderPartnerName: names[r.lenderPartnerId],
            borrowerPartnerName: names[r.borrowerPartnerId],
            lenderPartnerOrgNumber: orgNumbers[r.lenderPartnerId],
            borrowerPartnerOrgNumber: orgNumbers[r.borrowerPartnerId],
          ),
        )
        .toList();
  }

  static Future<VehicleRental> createRental({
    required String companyId,
    required String borrowerPartnerId,
    required PartnerVehicle vehicle,
    required DateTime rentalStartAt,
    required DateTime rentalEndAt,
  }) async {
    if (!_ok) throw StateError('Supabase ikke konfigurert');
    if (!rentalEndAt.isAfter(rentalStartAt)) {
      throw StateError('Sluttid må være etter starttid.');
    }

    final blocked = await fetchBlockedVehicleIds(companyId);
    if (blocked.contains(vehicle.id)) {
      throw StateError('Denne bilen er allerede i en aktiv utleie og er blokkert.');
    }

    final lenderPartnerId = await resolveOrCreateMaviLenderPartnerId(companyId);
    if (borrowerPartnerId == lenderPartnerId) {
      throw StateError('Låntaker kan ikke være MAVI Logistikk AS.');
    }
    final lender = await _client
        .from('partners')
        .select('name, is_active')
        .eq('id', lenderPartnerId)
        .maybeSingle();
    final lenderName = (lender?['name'] as String? ?? '').trim().toLowerCase();
    final lenderActive = lender?['is_active'] == true;
    if (!lenderActive || !lenderName.startsWith('mavi logistikk')) {
      throw StateError('Utleier må være aktiv MAVI Logistikk AS.');
    }

    final uid = _client.auth.currentUser?.id;
    final reg = vehicle.registrationNumber.trim();
    final row = {
      'company_id': companyId,
      'lender_partner_id': lenderPartnerId,
      'borrower_partner_id': borrowerPartnerId,
      'partner_vehicle_id': vehicle.id,
      'registration_number': reg,
      'vehicle_make': vehicleMakeFrom(vehicle),
      'unit_code': vehicle.unitCode,
      'rental_start': rentalStartAt.toIso8601String().split('T').first,
      'rental_end': rentalEndAt.toIso8601String().split('T').first,
      'rental_start_at': rentalStartAt.toUtc().toIso8601String(),
      'rental_end_at': rentalEndAt.toUtc().toIso8601String(),
      'status': 'pending_owner',
      if (uid != null) 'created_by': uid,
    };
    final inserted = await _client.from('vehicle_rentals').insert(row).select().single();
    final rental = VehicleRental.fromJson(inserted);

    try {
      await _client.rpc('notify_vehicle_rental_owner_sms', params: {'p_rental_id': rental.id});
      await PartnerService.flushSmsOutbox();
    } catch (_) {}

    final full = await fetchById(rental.id);
    return full ?? rental;
  }

  static Future<String> uploadPhoto({
    required String companyId,
    required String rentalId,
    required String slotKey,
    required Uint8List bytes,
    bool isReturn = false,
  }) async {
    final prefix = isReturn ? 'return_' : '';
    final path =
        '$companyId/vehicle_rentals/$rentalId/${prefix}${slotKey}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final stored = await CompanyFileStorage.upload(
      supabaseBucket: 'documents',
      storagePath: path,
      bytes: bytes,
      category: 'vehicle_rentals',
      fileName: '$prefix$slotKey.jpg',
    );
    return stored.path;
  }

  static Future<VehicleRental> updatePhotos(
    String rentalId,
    Map<String, String> photos, {
    bool isReturn = false,
  }) async {
    await _client.from('vehicle_rentals').update({
      if (isReturn) 'return_photos': photos else 'photos': photos,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', rentalId);
    return (await fetchById(rentalId))!;
  }

  static Future<VehicleRental> ownerSubmit({
    required String rentalId,
    required Map<String, String> photos,
    required String fuelLevel,
    required int odometerKm,
    String? ownerComment,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('vehicle_rentals').update({
      'photos': photos,
      'fuel_level': fuelLevel.trim(),
      'odometer_km': odometerKm,
      'owner_comment': ownerComment?.trim(),
      'agreement_accepted_at': now,
      'owner_submitted_at': now,
      'status': 'pending_mavi',
      'updated_at': now,
    }).eq('id', rentalId);
    return (await fetchById(rentalId))!;
  }

  static Future<VehicleRental> approveCheckout(String rentalId, {String? maviComment}) async {
    final row = await _client.rpc(
      'vehicle_rental_approve_checkout',
      params: {
        'p_rental_id': rentalId,
        'p_comment': maviComment,
      },
    );
    try {
      await PartnerService.flushSmsOutbox();
    } catch (_) {}
    final list = await _attachPartnerNames([VehicleRental.fromJson(row as Map<String, dynamic>)]);
    return list.first;
  }

  static Future<VehicleRental> reject(String rentalId, {String? reason}) async {
    final row = await _client.rpc(
      'vehicle_rental_reject',
      params: {
        'p_rental_id': rentalId,
        'p_reason': reason,
      },
    );
    try {
      await PartnerService.flushSmsOutbox();
    } catch (_) {}
    final list = await _attachPartnerNames([VehicleRental.fromJson(row as Map<String, dynamic>)]);
    return list.first;
  }

  static Future<VehicleRental> borrowerSubmitReturn({
    required String rentalId,
    required Map<String, String> returnPhotos,
    required String fuelLevel,
    required int odometerKm,
    String? comment,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('vehicle_rentals').update({
      'return_photos': returnPhotos,
      'return_fuel_level': fuelLevel.trim(),
      'return_odometer_km': odometerKm,
      'return_comment': comment?.trim(),
      'return_submitted_at': now,
      'status': 'pending_return_mavi',
      'updated_at': now,
    }).eq('id', rentalId);
    try {
      await _client.rpc(
        'notify_vehicle_rental_partner_sms',
        params: {'p_rental_id': rentalId, 'p_event': 'return_submitted'},
      );
      await PartnerService.flushSmsOutbox();
    } catch (_) {}
    return (await fetchById(rentalId))!;
  }

  static Future<VehicleRental> approveReturn(String rentalId, {String? maviComment}) async {
    final row = await _client.rpc(
      'vehicle_rental_approve_return',
      params: {
        'p_rental_id': rentalId,
        'p_comment': maviComment,
      },
    );
    try {
      await PartnerService.flushSmsOutbox();
    } catch (_) {}
    final list = await _attachPartnerNames([VehicleRental.fromJson(row as Map<String, dynamic>)]);
    return list.first;
  }

  static Future<void> cancel(String rentalId) async {
    await _client.from('vehicle_rentals').update({
      'status': 'cancelled',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', rentalId);
  }

  static Future<String> photoSignedUrl(String storagePath) =>
      PartnerService.resolveStorageUrl(storagePath);

  static Future<String> resolveOrCreateMaviLenderPartnerId(String companyId) async {
    final resolved = await _client.rpc(
      'resolve_mavi_borrower_partner_id',
      params: {'p_company_id': companyId},
    );
    if (resolved is String && resolved.isNotEmpty) return resolved;

    final existing = await _client
        .from('partners')
        .select('id')
        .eq('company_id', companyId)
        .eq('is_active', true)
        .ilike('name', 'mavi logistikk%')
        .limit(1)
        .maybeSingle();
    if (existing != null && existing['id'] is String) {
      return existing['id'] as String;
    }

    final inserted = await _client
        .from('partners')
        .insert({
          'company_id': companyId,
          'name': 'MAVI Logistikk AS',
          'trade_name': 'MAVI Logistikk AS',
          'is_active': true,
          'notes': 'Auto-opprettet for utleie (utleier)',
        })
        .select('id')
        .single();
    final id = inserted['id'] as String?;
    if (id == null || id.isEmpty) {
      throw StateError('Klarte ikke opprette/finne MAVI Logistikk AS som utleier.');
    }
    return id;
  }
}
