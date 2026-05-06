import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

import '../config/supabase_config.dart';
import '../../models/ticket.dart';
import '../../models/absence.dart';
import '../../models/department.dart';
import '../../models/risk_assessment.dart';
import '../../models/user_profile.dart';
import '../../models/sja_form.dart';
import '../../models/safety_round.dart';
import '../../models/hms_document.dart';
import '../../models/whistleblowing_report.dart';
import '../../models/kiosk_settings.dart';

/// Felles wrapper rundt Supabase-klienten med typed hjelpemetoder.
class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;
  static User? get currentUser => client.auth.currentUser;

  /// Sann hvis Supabase er konfigurert med ekte nøkler.
  static bool get isConfigured =>
      !SupabaseConfig.url.startsWith('YOUR_') &&
      !SupabaseConfig.anonKey.startsWith('YOUR_');

  // ── Tickets / avvik ──────────────────────────────────────────────────────

  /// Joiner reporter, ansvarlig og avdeling (PostgREST embed).
  static const String ticketSelectEmbed = '''
*,
reporter:profiles!reported_by(full_name, avatar_url),
assignee:profiles!assigned_to(full_name),
department:departments!department_id(name)
''';

  static Future<List<Ticket>> fetchTickets({
    String? companyId,
  }) async {
    if (!isConfigured) return const [];

    try {
      dynamic query = client
          .from('tickets')
          .select(ticketSelectEmbed);
      if (companyId != null) {
        query = query.eq('company_id', companyId);
      }
      final data =
          await query.order('created_at', ascending: false) as List<dynamic>;
      return data
          .map((e) => Ticket.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      dynamic q2 = client.from('tickets').select();
      if (companyId != null) {
        q2 = q2.eq('company_id', companyId);
      }
      final data = await q2.order('created_at', ascending: false) as List<dynamic>;
      return data
          .map((e) => Ticket.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  static Future<Ticket?> fetchTicketById(String id) async {
    if (!isConfigured) return null;
    try {
      final row = await client
          .from('tickets')
          .select(ticketSelectEmbed)
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      return Ticket.fromJson(row);
    } catch (_) {
      final row = await client.from('tickets').select().eq('id', id).maybeSingle();
      if (row == null) return null;
      return Ticket.fromJson(row);
    }
  }

  static Future<void> updateTicket(String id, Map<String, dynamic> patch) async {
    final merged = Map<String, dynamic>.from(patch);
    merged['updated_at'] = DateTime.now().toIso8601String();
    await client.from('tickets').update(merged).eq('id', id);
  }

  static Future<Ticket> createTicket(Ticket ticket) async {
    if (!isConfigured) throw StateError('Not configured');
    final inserted = await client
        .from('tickets')
        .insert(ticket.toInsertJson())
        .select()
        .single() as Map<String, dynamic>;
    return Ticket.fromJson(inserted);
  }

  static Future<List<TicketComment>> fetchTicketComments(String ticketId) async {
    final data = await client
        .from('ticket_comments')
        .select('*, profiles(full_name, avatar_url)')
        .eq('ticket_id', ticketId)
        .order('created_at', ascending: true) as List<dynamic>;
    return data.map((e) => TicketComment.fromJson(e)).toList();
  }

  static Future<void> addTicketComment({
    required String ticketId,
    required String comment,
    TicketStatus? newStatus,
    List<String> imageUrls = const [],
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    final current = await client
        .from('tickets')
        .select('status')
        .eq('id', ticketId)
        .single() as Map<String, dynamic>;

    final Map<String, dynamic> data = {
      'ticket_id': ticketId,
      'user_id': userId,
      'comment': comment,
      'image_urls': imageUrls,
    };

    if (newStatus != null) {
      data['old_status'] = current['status'];
      data['new_status'] = newStatus.dbValue;
      data['is_status_change'] = true;

      final upd = <String, dynamic>{
        'status': newStatus.dbValue,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (newStatus == TicketStatus.lukket) {
        upd['resolved_at'] = DateTime.now().toIso8601String();
        upd['resolved_by'] = userId;
      }
      await client.from('tickets').update(upd).eq('id', ticketId);
    }

    await client.from('ticket_comments').insert(data);
  }

  // ── Fravær ───────────────────────────────────────────────────────────────

  static Future<List<Absence>> fetchAbsences({
    String? userId,
    String? companyId,
    String? departmentId,
  }) async {
    if (!isConfigured) return const [];
    var query = client.from('absences').select('*, profiles(full_name, avatar_url, department_id)');
    if (userId != null) query = query.eq('user_id', userId);
    if (companyId != null) query = query.eq('company_id', companyId);
    final data = await query.order('start_date', ascending: false) as List<dynamic>;
    return data.map((e) => Absence.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Absence> createAbsence(Absence absence) async {
    if (!isConfigured) throw StateError('Not configured');
    final inserted = await client.from('absences').insert(absence.toInsertJson()).select().single();
    return Absence.fromJson(inserted);
  }

  static Future<void> updateAbsenceStatus(String id, AbsenceStatus status) async {
    await client.from('absences').update({
      'status': status.name,
      'approved_by': client.auth.currentUser?.id,
      'approved_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  static Future<void> deleteAbsence(String id) async {
    await client.from('absences').delete().eq('id', id);
  }

  static Future<AbsenceQuota?> fetchAbsenceQuota({required String userId, int? year}) async {
    final y = year ?? DateTime.now().year;
    final data = await client.from('absence_quotas').select().eq('user_id', userId).eq('year', y).maybeSingle();
    if (data == null) return null;
    return AbsenceQuota.fromJson(data);
  }

  static Future<List<AbsenceQuota>> fetchAbsenceQuotasForCompany({
    required String companyId,
    required int year,
  }) async {
    final data = await client
        .from('absence_quotas')
        .select()
        .eq('company_id', companyId)
        .eq('year', year)
        .order('user_id', ascending: true) as List<dynamic>;
    return data.map((e) => AbsenceQuota.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> updateAbsenceQuota(String userId, int year, Map<String, dynamic> updates) async {
    await client.from('absence_quotas').update(updates).eq('user_id', userId).eq('year', year);
  }

  static Future<void> createAbsenceQuota(AbsenceQuota quota) async {
    await client.from('absence_quotas').insert({
      'user_id': quota.userId,
      'year': quota.year,
      'vacation_days_total': quota.vacationDaysTotal,
      'vacation_days_carried_over': quota.vacationDaysCarriedOver,
    });
  }

  static Future<void> upsertAbsenceQuota({
    required String userId,
    required String companyId,
    required int year,
    int? vacationDaysTotal,
    int? vacationDaysCarriedOver,
  }) async {
    await client.from('absence_quotas').upsert({
      'user_id': userId,
      'company_id': companyId,
      'year': year,
      if (vacationDaysTotal != null) 'vacation_days_total': vacationDaysTotal,
      if (vacationDaysCarriedOver != null) 'vacation_days_carried_over': vacationDaysCarriedOver,
    }, onConflict: 'user_id,year');
  }

  static Future<void> runAnnualVacationCarryover() async {
    await client.rpc('annual_vacation_carryover');
  }

  // ── Risikoanalyser ──────────────────────────────────────────────────────

  static Future<List<RiskAssessment>> fetchRiskAssessments({String? companyId}) async {
    if (!isConfigured) return const [];
    final query = client.from('risk_assessments').select('*, profiles(full_name)');
    if (companyId != null) query.eq('company_id', companyId);
    final data = await query.order('created_at', ascending: false) as List<dynamic>;
    return data.map((e) => RiskAssessment.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<RiskAssessment> createRiskAssessment(RiskAssessment ra) async {
    final data = await client.from('risk_assessments').insert(ra.toInsertJson()).select().single();
    return RiskAssessment.fromJson(data);
  }

  // ── Whistleblowing / Anonym anmeldelse ──────────────────────────────────

  static Future<void> createWhistleblowingReport(WhistleblowingReport report) async {
    await client.from('whistleblowing_reports').insert(report.toJson());
  }

  static Future<List<WhistleblowingReport>> fetchWhistleblowingReports(String companyId) async {
    final data = await client
        .from('whistleblowing_reports')
        .select()
        .eq('company_id', companyId)
        .order('created_at', ascending: false) as List<dynamic>;
    return data.map((e) => WhistleblowingReport.fromJson(e)).toList();
  }

  // ── File Upload ─────────────────────────────────────────────────────────

  static Future<String> uploadFile(String bucket, String path, Uint8List bytes) async {
    await client.storage.from(bucket).uploadBinary(path, bytes);
    return client.storage.from(bucket).getPublicUrl(path);
  }

  // ── SJA ──────────────────────────────────────────────────────────────────

  static Future<List<SjaForm>> fetchSjaForms({String? companyId}) async {
    if (!isConfigured) return const [];
    final query = client.from('sja_forms').select('*, profiles(full_name)');
    if (companyId != null) query.eq('company_id', companyId);
    final data = await query.order('created_at', ascending: false) as List<dynamic>;
    return data.map((e) => SjaForm.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<SjaForm> createSjaForm(SjaForm sja) async {
    final data = await client.from('sja_forms').insert(sja.toInsertJson()).select().single();
    return SjaForm.fromJson(data);
  }

  static Future<void> updateSjaStatus(String id, SjaStatus status) async {
    await client.from('sja_forms').update({'status': status.name}).eq('id', id);
  }

  // ── Vernerunder (Safety Rounds) ──────────────────────────────────────────

  static Future<List<SafetyRound>> fetchSafetyRounds({String? companyId}) async {
    if (!isConfigured) return const [];
    final query = client.from('safety_rounds').select('*, profiles(full_name)');
    if (companyId != null) query.eq('company_id', companyId);
    final data = await query.order('created_at', ascending: false) as List<dynamic>;
    return data.map((e) => SafetyRound.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<SafetyRound> createSafetyRound(SafetyRound round) async {
    final data = await client.from('safety_rounds').insert(round.toInsertJson()).select().single();
    return SafetyRound.fromJson(data);
  }

  // ── Dokumenter ──────────────────────────────────────────────────────────

  static Future<List<HmsDocument>> fetchHmsDocuments({String? userId, String? companyId}) async {
    if (!isConfigured) return const [];
    var query = client.from('documents').select();
    if (userId != null) query = query.eq('user_id', userId);
    if (companyId != null) query = query.eq('company_id', companyId);
    final data = await query.order('created_at', ascending: false) as List<dynamic>;
    return data.map((e) => HmsDocument.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ── Avdelinger / profiler ───────────────────────────────────────────────

  static Future<List<Department>> fetchDepartments({String? companyId}) async {
    if (!isConfigured) return const [];
    final query = client.from('departments').select();
    if (companyId != null) query.eq('company_id', companyId);
    final data = await query.order('name', ascending: true);
    return (data as List).map((e) => Department.fromJson(e)).toList();
  }

  static Future<List<UserProfile>> fetchProfiles({String? companyId, String? departmentId}) async {
    if (!isConfigured) return const [];
    var query = client.from('profiles').select();
    if (companyId != null) query = query.eq('company_id', companyId);
    if (departmentId != null) query = query.eq('department_id', departmentId);
    final data = await query.order('full_name', ascending: true);
    return (data as List).map((e) => UserProfile.fromJson(e)).toList();
  }

  static Future<Department> createDepartment(Department dept) async {
    final data = await client.from('departments').insert(dept.toJson()).select().single();
    return Department.fromJson(data);
  }

  static Future<Department> updateDepartment(Department dept) async {
    final data = await client.from('departments').update(dept.toJson()).eq('id', dept.id).select().single();
    return Department.fromJson(data);
  }

  static Future<void> deleteDepartment(String id) async {
    await client.from('departments').delete().eq('id', id);
  }

  static Future<void> updateProfileDepartment(String profileId, String? departmentId) async {
    await client.from('profiles').update({'department_id': departmentId}).eq('id', profileId);
  }

  static Future<void> updateProfileRole(String profileId, UserRole role) async {
    await client.from('profiles').update({'role': role.name}).eq('id', profileId);
  }

  static Future<void> updateProfileAccess(String profileId, Map<String, dynamic> settings) async {
    await client.from('profiles').update({'access_settings': settings}).eq('id', profileId);
  }

  static Future<UserProfile?> fetchCurrentUserProfile() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return null;

      final data = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (data == null) {
        debugPrint('Profile not found for user: ${user.id}');
        return null;
      }
      return UserProfile.fromJson(data);
    } catch (e) {
      debugPrint('Error fetching current user profile: $e');
      return null;
    }
  }

  /// Henter profil, og oppretter en minimal pending-profil hvis trigger ikke gjorde det.
  static Future<UserProfile?> fetchOrCreateCurrentUserProfile() async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    try {
      await client.rpc('apply_partner_bootstrap_to_profile');
    } catch (_) {}

    var existing = await fetchCurrentUserProfile();
    if (existing == null) {
      try {
        await client.rpc('ensure_partner_profile_from_portal');
        existing = await fetchCurrentUserProfile();
      } catch (e) {
        debugPrint('ensure_partner_profile_from_portal: $e');
      }
    }

    if (existing != null) {
      try {
        await client.rpc('apply_partner_bootstrap_to_profile');
        existing = await fetchCurrentUserProfile();
      } catch (_) {}
      if (existing != null) {
        if (existing.companyId == null && existing.partnerId == null) {
          final bootstrapCompany = await discoverBootstrapCompanyId();
          if (bootstrapCompany != null) {
            try {
              await client.from('profiles').update({'company_id': bootstrapCompany}).eq('id', existing.id);
              return await fetchCurrentUserProfile();
            } catch (_) {}
          }
        }
        return existing;
      }
    }

    try {
      String fullName = (user.userMetadata?['full_name']?.toString() ??
              user.userMetadata?['name']?.toString() ??
              user.email?.split('@').first ??
              'Ny bruker')
          .trim();
      if (fullName.isEmpty) fullName = 'Ny bruker';

      final companyId = await discoverBootstrapCompanyId();

      await client.from('profiles').upsert({
        'id': user.id,
        'email': user.email ?? '${user.id}@unknown.local',
        'full_name': fullName,
        'role': 'ansatt',
        'company_id': companyId,
        'is_onboarded': false,
        'is_approved': false,
        'is_active': true,
      });

      return await fetchCurrentUserProfile();
    } catch (e) {
      debugPrint('Error creating fallback profile: $e');
      return null;
    }
  }

  static Future<String?> discoverBootstrapCompanyId() async {
    if (SupabaseConfig.defaultCompanyId != null) return SupabaseConfig.defaultCompanyId;
    try {
      final rpcVal = await client.rpc('get_bootstrap_company_id');
      if (rpcVal is String && rpcVal.isNotEmpty) return rpcVal;
    } catch (_) {}
    try {
      // Prioriter selskaper som allerede har avdelinger.
      final byDepartments = await client
          .from('departments')
          .select('company_id')
          .limit(1) as List<dynamic>;
      if (byDepartments.isNotEmpty && byDepartments.first['company_id'] != null) {
        return byDepartments.first['company_id'] as String;
      }
    } catch (_) {}
    try {
      final companies = await client.from('companies').select('id').limit(1) as List<dynamic>;
      if (companies.isNotEmpty) return companies.first['id'] as String;
    } catch (_) {}
    return null;
  }

  static Future<void> updateProfileAdminFields(
    String profileId, {
    String? fullName,
    String? phone,
    String? departmentId,
    UserRole? role,
    DateTime? birthDate,
    String? emergencyContactName,
    String? emergencyContactPhone,
    bool? approved,
  }) async {
    final patch = <String, dynamic>{};
    if (fullName != null) patch['full_name'] = fullName;
    if (phone != null) patch['phone'] = phone;
    if (departmentId != null) patch['department_id'] = departmentId;
    if (role != null) patch['role'] = role.name;
    if (birthDate != null) patch['birth_date'] = birthDate.toIso8601String().split('T').first;
    if (emergencyContactName != null) patch['emergency_contact_name'] = emergencyContactName;
    if (emergencyContactPhone != null) patch['emergency_contact_phone'] = emergencyContactPhone;
    if (approved != null) patch['is_approved'] = approved;
    if (patch.isEmpty) return;
    await client.from('profiles').update(patch).eq('id', profileId);
  }

  /// Permanent sletting av bruker (auth + profil + relaterte data via FK).
  static Future<void> deleteUserPermanently(String targetUserId) async {
    final me = client.auth.currentUser?.id;
    if (me == null) throw StateError('Ikke innlogget');
    if (me == targetUserId) {
      throw StateError('Du kan ikke slette din egen bruker.');
    }
    await client.rpc('admin_delete_user_hard', params: {
      'target_user_id': targetUserId,
    });
  }

  static Future<String?> getCurrentCompanyId() async {
    try {
      if (SupabaseConfig.defaultCompanyId != null) {
        return SupabaseConfig.defaultCompanyId;
      }
      
      final profile = await fetchCurrentUserProfile();
      if (profile?.companyId != null) return profile!.companyId;

      // Selv-healing: Hvis SuperAdmin mangler selskap, sett det til første tilgjengelige
      if (profile != null && profile.role == UserRole.superadmin) {
        final companies = await client.from('companies').select('id').limit(1) as List<dynamic>;
        if (companies.isNotEmpty) {
          final cid = companies[0]['id'] as String;
          await client.from('profiles').update({'company_id': cid}).eq('id', profile.id);
          return cid;
        }
      }
      return profile?.companyId;
    } catch (e) {
      debugPrint('Error getting company ID: $e');
      return null;
    }
  }

  /// Navn og infoskjerm-innstillinger for dashbord.
  static Future<({String? companyName, KioskSettings kiosk})>
      fetchCompanyDashboardMeta(String companyId) async {
    if (!isConfigured) {
      return (companyName: null, kiosk: KioskSettings.defaults);
    }
    try {
      final row = await client
          .from('companies')
          .select('name,kiosk_settings')
          .eq('id', companyId)
          .maybeSingle();
      if (row == null) {
        return (companyName: null, kiosk: KioskSettings.defaults);
      }
      final name = row['name'] as String?;
      final raw = row['kiosk_settings'];
      Map<String, dynamic>? map;
      if (raw is Map<String, dynamic>) {
        map = raw;
      } else if (raw is Map) {
        map = Map<String, dynamic>.from(raw);
      }
      return (
        companyName: name,
        kiosk: KioskSettings.fromJson(map),
      );
    } catch (e) {
      debugPrint('fetchCompanyDashboardMeta: $e');
      return (companyName: null, kiosk: KioskSettings.defaults);
    }
  }

  /// Kun admin/superadmin (sjekkes i databasen).
  static Future<KioskSettings> saveCompanyKioskSettings(
    KioskSettings settings,
  ) async {
    if (!isConfigured) throw StateError('Not configured');
    final result = await client.rpc(
      'set_company_kiosk_settings',
      params: {'p_settings': settings.toJson()},
    );
    if (result == null) return settings;
    final map = result is Map<String, dynamic>
        ? result
        : Map<String, dynamic>.from(result as Map);
    return KioskSettings.fromJson(map);
  }
}
