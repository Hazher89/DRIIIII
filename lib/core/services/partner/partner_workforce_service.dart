import 'package:excel/excel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/partner/partner_workforce.dart';
import '../../../models/partner/partner_links.dart';
import '../../utils/portal_credentials.dart';
import '../sms/sms_phone_utils.dart';
import 'partner_service.dart';

/// Ansatte + stempling for samarbeidspartnere (feature-flagget).
class PartnerWorkforceService {
  PartnerWorkforceService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<bool> isEnabled(String partnerId) async {
    final res = await _client.rpc(
      'partner_workforce_is_enabled',
      params: {'p_partner_id': partnerId},
    );
    return res == true;
  }

  static Future<void> setPartnerEnabled({
    required String partnerId,
    required bool enabled,
  }) async {
    await _client
        .from('partners')
        .update({'workforce_enabled': enabled})
        .eq('id', partnerId);
  }

  static Future<void> setCompanyWideEnabled({
    required String companyId,
    required bool enabled,
  }) async {
    await _client
        .from('companies')
        .update({'partner_workforce_enabled_all': enabled})
        .eq('id', companyId);
  }

  static Future<bool> companyWideEnabled(String companyId) async {
    final row = await _client
        .from('companies')
        .select('partner_workforce_enabled_all')
        .eq('id', companyId)
        .maybeSingle();
    return row?['partner_workforce_enabled_all'] == true;
  }

  static Future<List<PartnerStaff>> listStaff({
    required String partnerId,
    bool includeInactive = false,
  }) async {
    var q = _client.from('partner_staff').select().eq('partner_id', partnerId);
    if (!includeInactive) q = q.eq('is_active', true);
    final data = await q.order('full_name') as List<dynamic>;
    return data
        .map((e) => PartnerStaff.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<PartnerStaff> createStaff({
    required String partnerId,
    required String companyId,
    required String fullName,
    String? phone,
    String? address,
    String? postalCode,
    String? city,
    String? notes,
    String? createdBy,
  }) async {
    final row = await _client
        .from('partner_staff')
        .insert({
          'partner_id': partnerId,
          'company_id': companyId,
          'full_name': fullName.trim(),
          'phone': phone?.trim(),
          'address': address?.trim(),
          'postal_code': postalCode?.trim(),
          'city': city?.trim(),
          'notes': notes?.trim(),
          if (createdBy != null) 'created_by': createdBy,
        })
        .select()
        .single();
    return PartnerStaff.fromJson(Map<String, dynamic>.from(row));
  }

  static Future<PartnerStaff> updateStaff(PartnerStaff staff) async {
    final row = await _client
        .from('partner_staff')
        .update({
          'full_name': staff.fullName.trim(),
          'phone': staff.phone?.trim(),
          'address': staff.address?.trim(),
          'postal_code': staff.postalCode?.trim(),
          'city': staff.city?.trim(),
          'notes': staff.notes?.trim(),
          'is_active': staff.isActive,
          'deactivated_at': staff.isActive ? null : DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', staff.id)
        .select()
        .single();
    return PartnerStaff.fromJson(Map<String, dynamic>.from(row));
  }

  /// Deaktiver eller aktiver ansatt (stenger/åpner portal-innlogging).
  static Future<PartnerStaff> setStaffActive({
    required String staffId,
    required bool active,
  }) async {
    final row = await _client.rpc(
      'partner_staff_set_active',
      params: {
        'p_staff_id': staffId,
        'p_active': active,
      },
    );
    return PartnerStaff.fromJson(Map<String, dynamic>.from(row as Map));
  }

  /// Permanent sletting av ansatt + tilhørende timer/audit.
  static Future<Map<String, dynamic>> hardDeleteStaff(String staffId) async {
    final res = await _client.rpc(
      'partner_staff_hard_delete',
      params: {'p_staff_id': staffId},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<PartnerStaff> setCanManageRoutes({
    required String staffId,
    required bool enabled,
  }) async {
    final row = await _client.rpc(
      'partner_staff_set_can_manage_routes',
      params: {
        'p_staff_id': staffId,
        'p_enabled': enabled,
      },
    );
    return PartnerStaff.fromJson(Map<String, dynamic>.from(row as Map));
  }

  /// Innlogget brukers ansatt-rad (kun egen — GDPR).
  static Future<PartnerStaff?> myStaffRecord() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _client
        .from('partner_staff')
        .select()
        .eq('profile_id', uid)
        .eq('is_active', true)
        .maybeSingle();
    if (row == null) return null;
    return PartnerStaff.fromJson(Map<String, dynamic>.from(row));
  }

  /// Oppretter portalbruker (brukernavn/passord) for ansatt via eksisterende provision.
  static Future<PortalProvisionResult> provisionStaffLogin({
    required PartnerStaff staff,
    required String partnerName,
    String? usernameOverride,
    String? passwordOverride,
  }) async {
    final phone = staff.phone?.trim() ?? '';
    final normalized = normalizePhoneNo(phone);
    if (normalized == null) {
      throw StateError(
        'Ansatt må ha gyldig norsk mobil (8 siffer, start 4/9) før innlogging opprettes.',
      );
    }
    final phoneForProvision = displayPhoneNo(normalized);

    var username = (usernameOverride?.trim().isNotEmpty == true)
        ? usernameOverride!.trim().toLowerCase()
        : PortalCredentials.staffUsername(
            partnerName: partnerName,
            fullName: staff.fullName,
            phone: phoneForProvision,
            staffId: staff.id,
          );

    // Unikt aktivt brukernavn globalt (idx_partner_portal_username_active).
    for (var i = 0; i < 5; i++) {
      final clash = await _client
          .from('partner_portal_accounts')
          .select('id')
          .eq('is_active', true)
          .ilike('username', username)
          .maybeSingle();
      if (clash == null) break;
      username = '${username}${i + 2}';
      if (username.length > 28) {
        username = PortalCredentials.staffUsername(
          partnerName: partnerName,
          fullName: staff.fullName,
          phone: phoneForProvision,
          staffId: '${staff.id}$i',
        );
      }
    }

    final password = (passwordOverride?.trim().isNotEmpty == true)
        ? passwordOverride!.trim()
        : PortalCredentials.generatePassword();
    final loginEmail = PortalCredentials.loginEmail(
      partnerId: staff.partnerId,
      isOwner: false,
      isStaff: true,
      staffId: staff.id,
    );

    final res = await PartnerService.invokePortalProvisionRaw(
      partnerId: staff.partnerId,
      companyId: staff.companyId,
      partnerVehicleId: staff.id, // unik scope for auth-e-post (ikke kjøretøy)
      username: username,
      loginEmail: loginEmail,
      phone: phoneForProvision,
      password: password,
      driverName: staff.fullName,
      accountKind: 'staff',
      sendCredentialsSms: false,
    );

    // Koble portal_account / profile til staff-rad (kun denne ansatte).
    final accounts = await PartnerService.fetchPortalAccounts(staff.partnerId);
    PartnerPortalAccount? match;
    for (final a in accounts) {
      if (a.accountKind == 'staff' &&
          a.username.toLowerCase() == res.username.toLowerCase()) {
        match = a;
        break;
      }
    }
    if (match != null) {
      await _client.from('partner_staff').update({
        'portal_account_id': match.id,
        'profile_id': match.profileId,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', staff.id);
    }

    return res;
  }

  /// Nytt passord for eksisterende ansatt-innlogging (enkelt for bil-eier).
  static Future<PortalProvisionResult> resetStaffPassword({
    required PartnerStaff staff,
    required String partnerName,
  }) async {
    if (staff.portalAccountId == null && staff.profileId == null) {
      throw StateError('Ansatt har ingen innlogging ennå — bruk «Lag bruker» først.');
    }
    final phone = staff.phone?.trim() ?? '';
    final normalized = normalizePhoneNo(phone);
    if (normalized == null) {
      throw StateError('Gyldig mobilnummer kreves for å lage nytt passord.');
    }

    String username = 'ansatt';
    final accounts = await PartnerService.fetchPortalAccounts(staff.partnerId);
    PartnerPortalAccount? match;
    for (final a in accounts) {
      if (staff.portalAccountId != null && a.id == staff.portalAccountId) {
        match = a;
        break;
      }
      if (a.accountKind == 'staff' &&
          staff.profileId != null &&
          a.profileId == staff.profileId) {
        match = a;
        break;
      }
    }
    if (match != null) username = match.username;

    final password = PortalCredentials.generatePassword();
    final loginEmail = match?.loginEmail ??
        PortalCredentials.loginEmail(
          partnerId: staff.partnerId,
          isOwner: false,
          isStaff: true,
          staffId: staff.id,
        );

    return PartnerService.invokePortalProvisionRaw(
      partnerId: staff.partnerId,
      companyId: staff.companyId,
      partnerVehicleId: staff.id,
      portalAccountId: match?.id ?? staff.portalAccountId,
      username: username,
      loginEmail: loginEmail,
      phone: displayPhoneNo(normalized),
      password: password,
      driverName: staff.fullName,
      accountKind: 'staff',
      sendCredentialsSms: false,
      regeneratePassword: true,
    );
  }

  static String formatHours(Duration? d) {
    if (d == null) return '—';
    final h = d.inMinutes / 60.0;
    if (h < 0.05) return '0 t';
    return '${h.toStringAsFixed(h >= 10 ? 1 : 1)} t';
  }

  static String formatDurationClock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h <= 0) return '${m}m';
    return '${h}t ${m.toString().padLeft(2, '0')}m';
  }

  static Future<List<PartnerTimeEntry>> listEntries({
    required String partnerId,
    DateTime? from,
    DateTime? to,
    String? staffId,
    bool includeDeleted = false,
  }) async {
    var q = _client
        .from('partner_time_entries')
        .select('*, partner_staff(full_name)')
        .eq('partner_id', partnerId);
    if (!includeDeleted) q = q.eq('is_deleted', false);
    if (staffId != null) q = q.eq('staff_id', staffId);
    if (from != null) q = q.gte('clock_in', from.toUtc().toIso8601String());
    if (to != null) q = q.lte('clock_in', to.toUtc().toIso8601String());
    final data = await q.order('clock_in', ascending: false) as List<dynamic>;
    return data
        .map((e) => PartnerTimeEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<Map<String, dynamic>> punch() async {
    final res = await _client.rpc('partner_workforce_punch');
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<PartnerTimeEntry> upsertManualEntry({
    required String partnerId,
    required String companyId,
    required String staffId,
    required DateTime clockIn,
    DateTime? clockOut,
    String? note,
    String? entryId,
    required String editorId,
    required bool isAdmin,
    String? reason,
  }) async {
    final source = isAdmin ? 'admin_edit' : 'owner_edit';
    if (entryId == null) {
      final row = await _client
          .from('partner_time_entries')
          .insert({
            'partner_id': partnerId,
            'company_id': companyId,
            'staff_id': staffId,
            'clock_in': clockIn.toUtc().toIso8601String(),
            'clock_out': clockOut?.toUtc().toIso8601String(),
            'note': note,
            'source': 'manual',
            'created_by': editorId,
            'updated_by': editorId,
          })
          .select('*, partner_staff(full_name)')
          .single();
      return PartnerTimeEntry.fromJson(Map<String, dynamic>.from(row));
    }

    final row = await _client
        .from('partner_time_entries')
        .update({
          'clock_in': clockIn.toUtc().toIso8601String(),
          'clock_out': clockOut?.toUtc().toIso8601String(),
          'note': note,
          'source': source,
          'updated_by': editorId,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', entryId)
        .select('*, partner_staff(full_name)')
        .single();

    return PartnerTimeEntry.fromJson(Map<String, dynamic>.from(row));
  }

  static Future<void> softDeleteEntry({
    required String entryId,
    required String editorId,
  }) async {
    await _client.from('partner_time_entries').update({
      'is_deleted': true,
      'deleted_at': DateTime.now().toIso8601String(),
      'updated_by': editorId,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', entryId);
  }

  static Future<List<PartnerTimeAudit>> listAudits({
    required String partnerId,
    String? entryId,
  }) async {
    var q = _client
        .from('partner_time_entry_audits')
        .select('*, profiles(full_name, email)')
        .eq('partner_id', partnerId);
    if (entryId != null) q = q.eq('entry_id', entryId);
    final data = await q.order('changed_at', ascending: false).limit(200) as List<dynamic>;
    return data
        .map((e) => PartnerTimeAudit.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Excel (.xlsx) bytes for timer.
  static List<int> buildExcelBytes({
    required String partnerName,
    required List<PartnerTimeEntry> entries,
  }) {
    final excel = Excel.createExcel();
    final sheet = excel['Timer'];
    excel.delete('Sheet1');
    sheet.appendRow([
      TextCellValue('Ansatt'),
      TextCellValue('Inn'),
      TextCellValue('Ut'),
      TextCellValue('Timer'),
      TextCellValue('Kilde'),
      TextCellValue('Merknad'),
    ]);
    for (final e in entries) {
      final hours = e.duration != null
          ? (e.duration!.inMinutes / 60.0).toStringAsFixed(2)
          : '';
      sheet.appendRow([
        TextCellValue(e.staffName ?? e.staffId),
        TextCellValue(e.clockIn.toLocal().toIso8601String()),
        TextCellValue(e.clockOut?.toLocal().toIso8601String() ?? ''),
        TextCellValue(hours),
        TextCellValue(e.source),
        TextCellValue(e.note ?? ''),
      ]);
    }
    final meta = excel['Info'];
    meta.appendRow([TextCellValue('Bedrift'), TextCellValue(partnerName)]);
    meta.appendRow([
      TextCellValue('Eksportert'),
      TextCellValue(DateTime.now().toIso8601String()),
    ]);
    return excel.encode() ?? [];
  }
}
