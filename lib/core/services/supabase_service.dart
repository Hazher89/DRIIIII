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

/// Felles wrapper rundt Supabase-klienten med typed hjelpemetoder.
class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;
  static User? get currentUser => client.auth.currentUser;

  /// Sann hvis Supabase er konfigurert med ekte nøkler.
  static bool get isConfigured =>
      !SupabaseConfig.url.startsWith('YOUR_') &&
      !SupabaseConfig.anonKey.startsWith('YOUR_');

  // ── Tickets / avvik ──────────────────────────────────────────────────────

  static Future<List<Ticket>> fetchTickets({
    String? companyId,
  }) async {
    if (!isConfigured) return const [];

    final query = client.from('tickets').select();
    if (companyId != null) {
      query.eq('company_id', companyId);
    }

    final data =
        await query.order('created_at', ascending: false) as List<dynamic>;

    return data
        .map((e) => Ticket.fromJson(e as Map<String, dynamic>))
        .toList();
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

    final Map<String, dynamic> data = {
      'ticket_id': ticketId,
      'user_id': userId,
      'comment': comment,
      'image_urls': imageUrls,
    };

    if (newStatus != null) {
      data['new_status'] = newStatus.dbValue;
      data['is_status_change'] = true;
      
      // Also update the ticket itself
      await client.from('tickets').update({
        'status': newStatus.dbValue,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', ticketId);
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
}
