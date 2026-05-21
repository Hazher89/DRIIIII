import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../../models/ticket.dart';
import '../../models/absence.dart';
import '../constants/leave_rules.dart';
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
  /// Unngår at web-klienten henger evig på RPC (viser bare «Klargjør profil …»).
  static const Duration _rpcTimeout = Duration(seconds: 8);
  static const Duration _writeTimeout = Duration(seconds: 14);
  static const Duration _fetchOrCreateHardTimeout = Duration(seconds: 45);

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> _silentRpcTimeout(String rpcName, {Duration? timeout}) async {
    try {
      await client.rpc(rpcName).timeout(timeout ?? _rpcTimeout);
    } catch (e) {
      debugPrint('RPC $rpcName: $e');
    }
  }

  static User? get currentUser => client.auth.currentUser;

  /// Eiere av systemet — alltid superadmin etter innlogging.
  static const superadminEmails = {
    'baxigshti@gmail.com',
    'baxightsi@gmail.com',
    'baxigshti@hotmail.de',
    // Vanlig skrivefeil (i/l) ved Google-innlogging — samme eier
    'baxlgshtl@gmail.com',
  };

  static bool _isSuperadminEmail(String? email) {
    if (email == null) return false;
    return superadminEmails.contains(email.trim().toLowerCase());
  }

  /// Når DB/RPC feiler: tillat innlogging for whitelisted eier-e-post (superadmin i minnet).
  /// Må fortsatt rette `profiles` i Supabase for normal drift.
  static UserProfile? emergencySuperadminProfileFromSession() {
    if (!isConfigured) return null;
    final u = currentUser;
    if (u == null) return null;
    final email = u.email?.trim().toLowerCase();
    if (email == null || email.isEmpty) return null;
    if (!superadminEmails.contains(email)) return null;
    final name = email.split('@').first;
    return UserProfile(
      id: u.id,
      email: email,
      fullName: name,
      role: UserRole.superadmin,
      isOnboarded: true,
      isApproved: true,
      isActive: true,
      isRecoverySession: true,
    );
  }

  /// Etter manuell SQL i Supabase: kall for å synke `profiles` uten å blokkere UI.
  static Future<void> rpcEnsureInternalProfileMissing() async {
    if (!isConfigured) return;
    try {
      await client.rpc('ensure_internal_profile_missing').timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('rpcEnsureInternalProfileMissing: $e');
    }
  }

  /// Profil for UI — sikrer at [company_id] er satt (RLS blokkerer data uten).
  static Future<UserProfile?> fetchEffectiveUserProfile() =>
      ensureSessionLinkedToCompany();

  /// Kobler innlogget bruker til et selskap i `profiles` (nødvendig for RLS/data).
  static Future<UserProfile?> ensureSessionLinkedToCompany() async {
    if (!isConfigured) return null;
    final user = currentUser;
    if (user == null) return null;

    final email = user.email?.trim().toLowerCase() ?? '';
    final isPortal =
        email.endsWith('.portal') || email.endsWith('@portal.driftpro.no');

    if (!isPortal) {
      await rpcEnsureInternalProfileMissing();
    } else {
      try {
        await client.rpc('ensure_partner_profile_from_portal').timeout(_rpcTimeout);
      } catch (e) {
        debugPrint('ensure_partner_profile_from_portal: $e');
      }
    }

    await _silentRpcTimeout('apply_partner_bootstrap_to_profile');

    var profile = await fetchCurrentUserProfile();
    profile = profile != null ? await _ensureSuperadminIfOwner(profile) : null;

    final bootstrap = await discoverBootstrapCompanyId();

    if (profile != null &&
        profile.companyId == null &&
        profile.partnerId == null &&
        bootstrap != null) {
      try {
        await client
            .from('profiles')
            .update({'company_id': bootstrap})
            .eq('id', profile.id)
            .timeout(_writeTimeout);
        profile = await fetchCurrentUserProfile();
        if (profile != null) profile = await _ensureSuperadminIfOwner(profile);
      } catch (e) {
        debugPrint('ensureSessionLinkedToCompany update company_id: $e');
      }
    }

    if (profile == null && _isSuperadminEmail(email) && bootstrap != null) {
      try {
        final fn = email.split('@').first;
        await client.from('profiles').upsert({
          'id': user.id,
          'email': email,
          'full_name': fn.isEmpty ? 'Bruker' : fn,
          'company_id': bootstrap,
          'role': 'superadmin',
          'is_onboarded': true,
          'is_approved': true,
          'is_active': true,
        }).timeout(_writeTimeout);
        profile = await fetchCurrentUserProfile();
        if (profile != null) profile = await _ensureSuperadminIfOwner(profile);
      } catch (e) {
        debugPrint('ensureSessionLinkedToCompany superadmin upsert: $e');
      }
    }

    if (profile != null) {
      if (profile.companyId != null) return profile;
      if (bootstrap != null) {
        return profile.copyWith(companyId: bootstrap);
      }
      return profile;
    }

    final recovery = emergencySuperadminProfileFromSession();
    if (recovery == null) return null;
    return bootstrap != null ? recovery.copyWith(companyId: bootstrap) : recovery;
  }

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
    var query = client.from('absences').select(
      '*, profiles!absences_user_id_fkey(full_name, avatar_url, department_id)',
    );
    if (userId != null) query = query.eq('user_id', userId);
    if (companyId != null) query = query.eq('company_id', companyId);
    if (departmentId != null) query = query.eq('department_id', departmentId);
    final data = await query.order('start_date', ascending: false) as List<dynamic>;
    return data.map((e) => Absence.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Absence> createAbsence(Absence absence, {String? approverId}) async {
    if (!isConfigured) throw StateError('Not configured');
    final approver = approverId ?? client.auth.currentUser?.id;
    final inserted = await client
        .from('absences')
        .insert(absence.toInsertJson(approverId: approver))
        .select(
          '*, profiles!absences_user_id_fkey(full_name, avatar_url, department_id)',
        )
        .single();
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
    final data = await client
        .from('absence_quotas')
        .select()
        .eq('user_id', userId)
        .eq('year', y)
        .maybeSingle();
    if (data == null) return null;
    return AbsenceQuota.fromJson(data);
  }

  /// Henter eller oppretter årets ferie-/fraværssaldo (kalles «saldo» i UI).
  static Future<AbsenceQuota> ensureAbsenceQuota({
    required String userId,
    required String companyId,
    int? year,
  }) async {
    final y = year ?? DateTime.now().year;
    final existing = await fetchAbsenceQuota(userId: userId, year: y);
    if (existing != null) return existing;

    try {
      final row = await client.rpc(
        'ensure_absence_quota',
        params: {'p_user_id': userId, 'p_year': y},
      );
      if (row is Map<String, dynamic>) {
        return AbsenceQuota.fromJson(row);
      }
    } catch (_) {
      // RPC ikke deployet ennå — prøv direkte upsert (admin) eller vis feil.
    }

    try {
      await upsertAbsenceQuota(
        userId: userId,
        companyId: companyId,
        year: y,
        vacationDaysTotal: LeaveRules.ferieLegalMinimumDays,
      );
      final created = await fetchAbsenceQuota(userId: userId, year: y);
      if (created != null) return created;
    } catch (_) {}

    throw StateError(
      'Kunne ikke opprette feriedager for $y. Be admin om å dele ut feriedager, '
      'eller kjør migrasjonen absence_quota_auto_provision.sql i Supabase.',
    );
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

  static Future<List<AbsenceQuota>> fetchAbsenceQuotasForCompanyRange({
    required String companyId,
    required int fromYear,
    required int toYear,
  }) async {
    final data = await client
        .from('absence_quotas')
        .select()
        .eq('company_id', companyId)
        .gte('year', fromYear)
        .lte('year', toYear)
        .order('year', ascending: true) as List<dynamic>;
    return data.map((e) => AbsenceQuota.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Map<String, dynamic>> carryoverVacationBetweenYears({
    required String companyId,
    required int fromYear,
    int? toYear,
    String? userId,
  }) async {
    final result = await client.rpc(
      'carryover_vacation_between_years',
      params: {
        'p_company_id': companyId,
        'p_from_year': fromYear,
        'p_to_year': toYear ?? fromYear + 1,
        'p_user_id': userId,
      },
    );
    if (result is Map<String, dynamic>) return result;
    return Map<String, dynamic>.from(result as Map);
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

  static Future<int> distributeVacationDays({
    required String companyId,
    required int year,
    required int days,
  }) async {
    final result = await client.rpc(
      'distribute_vacation_days',
      params: {
        'p_company_id': companyId,
        'p_year': year,
        'p_days': days,
      },
    );
    return result as int? ?? 0;
  }

  static Future<CompanyLeaveSettings> fetchCompanyLeaveSettings(String companyId) async {
    final data = await client
        .from('companies')
        .select(
          'egenmelding_days_per_year, egenmelding_consecutive_max, max_vacation_carryover',
        )
        .eq('id', companyId)
        .single();
    return CompanyLeaveSettings.fromJson(data);
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
    final depts = (data as List).map((e) => Department.fromJson(e)).toList();
    if (depts.isEmpty) return depts;

    final leaderMap = await fetchDepartmentLeaderIdsByDepartment(
      depts.map((d) => d.id).toList(),
    );
    return depts
        .map(
          (d) => Department(
            id: d.id,
            companyId: d.companyId,
            name: d.name,
            description: d.description,
            leaderId: d.leaderId,
            leaderIds: leaderMap[d.id] ?? d.leaderIds,
            colorCode: d.colorCode,
            iconName: d.iconName,
            parentDepartmentId: d.parentDepartmentId,
            createdAt: d.createdAt,
          ),
        )
        .toList();
  }

  static Future<Map<String, List<String>>> fetchDepartmentLeaderIdsByDepartment(
    List<String> departmentIds,
  ) async {
    if (!isConfigured || departmentIds.isEmpty) return {};
    try {
      final data = await client
          .from('department_leaders')
          .select('department_id, profile_id')
          .inFilter('department_id', departmentIds);
      final map = <String, List<String>>{};
      for (final row in data as List) {
        final deptId = row['department_id'] as String;
        final profileId = row['profile_id'] as String;
        map.putIfAbsent(deptId, () => []).add(profileId);
      }
      return map;
    } catch (e) {
      debugPrint('fetchDepartmentLeaderIdsByDepartment: $e');
      return {};
    }
  }

  static Future<void> setDepartmentLeaders(
    String departmentId,
    List<String> profileIds,
  ) async {
    await client.rpc('set_department_leaders', params: {
      'p_department_id': departmentId,
      'p_leader_ids': profileIds,
    });
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
    try {
      await client.from('employee_login_accounts').update({
        'department_id': departmentId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('profile_id', profileId);
    } catch (e) {
      debugPrint('updateProfileDepartment employee_login_accounts: $e');
    }
  }

  static Future<void> updateProfileRole(String profileId, UserRole role) async {
    await client.from('profiles').update({'role': role.name}).eq('id', profileId);
  }

  static Future<void> updateProfileAccess(String profileId, Map<String, dynamic> settings) async {
    await client.from('profiles').update({'access_settings': settings}).eq('id', profileId);
  }

  /// Godkjenner ny ansatt med rolle, avdeling og granulære tilganger (kun superadmin i DB).
  static Future<void> approveEmployee({
    required String profileId,
    required UserRole role,
    required String? departmentId,
    required Map<String, dynamic> accessSettings,
    bool setDepartmentLeader = false,
  }) async {
    await client.rpc('approve_employee_profile', params: {
      'p_profile_id': profileId,
      'p_role': role.name,
      'p_department_id': departmentId,
      'p_access_settings': accessSettings,
      'p_set_department_leader': setDepartmentLeader,
    });
  }

  /// Oppdaterer rolle, avdeling, tilganger og godkjenningsstatus.
  static Future<void> updateEmployeeAccess({
    required String profileId,
    required UserRole role,
    required String? departmentId,
    required Map<String, dynamic> accessSettings,
    required bool isApproved,
    bool setDepartmentLeader = false,
  }) async {
    await client.from('profiles').update({
      'role': role.name,
      'department_id': departmentId,
      'access_settings': accessSettings,
      'is_approved': isApproved,
      'is_active': isApproved,
    }).eq('id', profileId);

    if (setDepartmentLeader && departmentId != null) {
      await client.rpc('add_department_leader', params: {
        'p_department_id': departmentId,
        'p_profile_id': profileId,
      });
    }
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
      final profile = UserProfile.fromJson(
        Map<String, dynamic>.from(data),
        fallbackAuthUserId: user.id,
        fallbackAuthEmail: user.email,
      );
      return await _ensureSuperadminIfOwner(profile);
    } catch (e) {
      debugPrint('Error fetching current user profile: $e');
      return null;
    }
  }

  /// Henter profil med noen forsøk (Auth → profil-race ved første innlogging).
  static Future<UserProfile?> fetchOrCreateCurrentUserProfile() async {
    try {
      return await _fetchOrCreateCurrentUserProfileWithRetries().timeout(
        _fetchOrCreateHardTimeout,
        onTimeout: () {
          debugPrint(
            'fetchOrCreateCurrentUserProfile: ga opp etter ${_fetchOrCreateHardTimeout.inSeconds}s (timeout)',
          );
          return null;
        },
      );
    } catch (e, st) {
      debugPrint('fetchOrCreateCurrentUserProfile failed: $e\n$st');
      return null;
    }
  }

  static Future<UserProfile?> _fetchOrCreateCurrentUserProfileWithRetries() async {
    const attempts = 4;
    for (var i = 0; i < attempts; i++) {
      if (i > 0) await Future.delayed(Duration(milliseconds: 300 * i));
      final profile = await _fetchOrCreateCurrentUserProfileOnce();
      if (profile != null) return profile;
    }
    return null;
  }

  /// Én runde: hent/opprett profil og partner-bootstrap.
  static Future<UserProfile?> _fetchOrCreateCurrentUserProfileOnce() async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    await _silentRpcTimeout('apply_partner_bootstrap_to_profile');

    var existing = await fetchCurrentUserProfile();
    if (existing == null) {
      try {
        await client.rpc('ensure_partner_profile_from_portal').timeout(_rpcTimeout);
        existing = await fetchCurrentUserProfile();
      } catch (e) {
        debugPrint('ensure_partner_profile_from_portal: $e');
      }
    }

    // Interne/admin uten profilrad: RLS blokkerer som regel klient-upsert via Flutter.
    if (existing == null) {
      try {
        await client.rpc('ensure_internal_profile_missing').timeout(_rpcTimeout);
        existing = await fetchCurrentUserProfile();
      } catch (e) {
        debugPrint('ensure_internal_profile_missing: $e');
      }
    }

    if (existing != null) {
      existing = await _ensureSuperadminIfOwner(existing);
      await _silentRpcTimeout('apply_partner_bootstrap_to_profile');
      existing = await fetchCurrentUserProfile();
      if (existing != null) {
        if (existing.companyId == null && existing.partnerId == null) {
          final bootstrapCompany = await discoverBootstrapCompanyId();
          if (bootstrapCompany != null) {
            try {
              await client
                  .from('profiles')
                  .update({'company_id': bootstrapCompany})
                  .eq('id', existing.id)
                  .timeout(_writeTimeout);
              return await fetchCurrentUserProfile();
            } catch (e) {
              debugPrint('profiles update company_id: $e');
            }
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

      await client
          .from('profiles')
          .upsert({
            'id': user.id,
            'email': user.email ?? '${user.id}@unknown.local',
            'full_name': fullName,
            'role': 'ansatt',
            'company_id': companyId,
            'is_onboarded': false,
            'is_approved': false,
            'is_active': true,
          })
          .timeout(_writeTimeout);

      final created = await fetchCurrentUserProfile();
      if (created != null) return await _ensureSuperadminIfOwner(created);
    } catch (e) {
      debugPrint('Error creating fallback profile: $e');
    }

    final linked = await ensureSessionLinkedToCompany();
    if (linked != null) {
      if (linked.isRecoverySession) {
        debugPrint(
          'recoverySession: data i Supabase krever profiles-rad — kjør ensure_internal_profile_missing.sql i SQL Editor.',
        );
      }
      return linked;
    }

    return null;
  }

  /// Løfter eier-e-post til superadmin hvis DB-trigger hadde feil e-post.
  static Future<UserProfile> _ensureSuperadminIfOwner(UserProfile profile) async {
    if (!_isSuperadminEmail(profile.email)) return profile;
    if (profile.role == UserRole.superadmin &&
        profile.isApproved &&
        profile.isOnboarded) {
      return profile;
    }
    try {
      await client
          .from('profiles')
          .update({
            'role': 'superadmin',
            'is_approved': true,
            'is_onboarded': true,
            'is_active': true,
          })
          .eq('id', profile.id)
          .timeout(_writeTimeout);
      final refreshed = await fetchCurrentUserProfile();
      return refreshed ?? profile.copyWith(
        role: UserRole.superadmin,
        isApproved: true,
        isOnboarded: true,
        isActive: true,
      );
    } catch (e) {
      debugPrint('ensureSuperadminIfOwner: $e');
      return profile.copyWith(
        role: UserRole.superadmin,
        isApproved: true,
        isOnboarded: true,
        isActive: true,
      );
    }
  }

  static Future<String?> discoverBootstrapCompanyId() async {
    if (SupabaseConfig.defaultCompanyId != null) return SupabaseConfig.defaultCompanyId;
    try {
      final rpcVal =
          await client.rpc('get_bootstrap_company_id').timeout(_rpcTimeout);
      if (rpcVal is String && rpcVal.isNotEmpty) return rpcVal;
    } catch (_) {}
    try {
      // Prioriter selskaper som allerede har avdelinger.
      final byDepartments = await client
              .from('departments')
              .select('company_id')
              .limit(1)
              .timeout(_rpcTimeout)
          as List<dynamic>;
      if (byDepartments.isNotEmpty && byDepartments.first['company_id'] != null) {
        return byDepartments.first['company_id'] as String;
      }
    } catch (_) {}
    try {
      final companies =
          await client.from('companies').select('id').limit(1).timeout(_rpcTimeout) as List<dynamic>;
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
    await updateEmployeeProfile(
      profileId,
      fullName: fullName,
      phone: phone,
      departmentId: departmentId,
      role: role,
      birthDate: birthDate,
      emergencyContactName: emergencyContactName,
      emergencyContactPhone: emergencyContactPhone,
    );
    if (approved != null) {
      await client.from('profiles').update({'is_approved': approved}).eq('id', profileId);
    }
  }

  /// Full oppdatering av ansattprofil (telefon → Sveve via phone_normalized trigger).
  static Future<void> updateEmployeeProfile(
    String profileId, {
    String? fullName,
    String? phone,
    String? address,
    String? jobTitle,
    String? employeeNumber,
    String? departmentId,
    UserRole? role,
    DateTime? birthDate,
    DateTime? hireDate,
    String? emergencyContactName,
    String? emergencyContactPhone,
    bool? isSafetyRepresentative,
    bool? isActive,
    bool? smsOptIn,
  }) async {
    final patch = <String, dynamic>{};
    if (fullName != null) patch['full_name'] = fullName;
    if (phone != null) patch['phone'] = phone.trim().isEmpty ? null : phone.trim();
    if (address != null) patch['address'] = address.trim().isEmpty ? null : address.trim();
    if (jobTitle != null) patch['job_title'] = jobTitle.trim().isEmpty ? null : jobTitle.trim();
    if (employeeNumber != null) {
      patch['employee_number'] =
          employeeNumber.trim().isEmpty ? null : employeeNumber.trim();
    }
    if (departmentId != null) patch['department_id'] = departmentId;
    if (role != null) patch['role'] = role.name;
    if (birthDate != null) {
      patch['birth_date'] = birthDate.toIso8601String().split('T').first;
    }
    if (hireDate != null) {
      patch['hire_date'] = hireDate.toIso8601String().split('T').first;
    }
    if (emergencyContactName != null) {
      patch['emergency_contact_name'] =
          emergencyContactName.trim().isEmpty ? null : emergencyContactName.trim();
    }
    if (emergencyContactPhone != null) {
      patch['emergency_contact_phone'] =
          emergencyContactPhone.trim().isEmpty ? null : emergencyContactPhone.trim();
    }
    if (isSafetyRepresentative != null) {
      patch['is_safety_representative'] = isSafetyRepresentative;
    }
    if (isActive != null) patch['is_active'] = isActive;
    if (smsOptIn != null) patch['sms_opt_in'] = smsOptIn;
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

      final profile = await ensureSessionLinkedToCompany();
      if (profile?.companyId != null) return profile!.companyId;

      return discoverBootstrapCompanyId();
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
