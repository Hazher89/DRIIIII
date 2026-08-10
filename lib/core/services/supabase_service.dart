import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'notification/notification_outbox_service.dart';
import '../utils/norwegian_national_id.dart';
import '../../models/ticket.dart';
import '../../models/ticket_assignee_options.dart';
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
    'hazher@mavilogistikk.no',
  };

  /// Ansattnummer som alltid skal ha superadmin (Hazher = 25).
  static const superadminEmployeeNumbers = {'25'};

  static bool _isSuperadminEmail(String? email) {
    if (email == null) return false;
    return superadminEmails.contains(email.trim().toLowerCase());
  }

  static const superadminDisplayName = 'Hazher';

  static bool _isMaviEmployeeEmail(String? email) {
    if (email == null) return false;
    return email.trim().toLowerCase().endsWith('@mavi-employees.driftpro.no');
  }

  static bool emailLooksLikePortal(String? email) {
    final e = email?.trim().toLowerCase() ?? '';
    return e.endsWith('.portal') || e.endsWith('@portal.driftpro.no');
  }

  /// Intern MAVI-/eier-sesjon — aldri partnerportal, selv om samme person har bedrift.
  static bool isInternalStaffSession({UserProfile? profile, String? email}) {
    final em = (email ?? currentUser?.email)?.trim().toLowerCase() ?? '';
    if (_isMaviEmployeeEmail(em) || _isSuperadminEmail(em)) return true;
    if (profile != null) {
      if (_isMaviEmployeeEmail(profile.email) || _isSuperadminEmail(profile.email)) {
        return true;
      }
      final no = profile.employeeNumber?.trim();
      if (no != null &&
          no.isNotEmpty &&
          superadminEmployeeNumbers.contains(no)) {
        return true;
      }
      if (profile.role == UserRole.superadmin || profile.role == UserRole.admin) {
        return true;
      }
    }
    return false;
  }

  /// Sjekker om innlogget bruker har aktiv rad i partner_portal_accounts.
  static Future<bool> currentSessionHasActivePortalAccount() async {
    if (!isConfigured) return false;
    final user = currentUser;
    if (user == null) return false;
    // Ansattnummer-innlogging (f.eks. #25) vinner alltid over portal-kobling.
    if (isInternalStaffSession(email: user.email)) return false;
    if (emailLooksLikePortal(user.email)) return true;
    try {
      final byProfile = await client
          .from('partner_portal_accounts')
          .select('id')
          .eq('is_active', true)
          .eq('profile_id', user.id)
          .maybeSingle()
          .timeout(_rpcTimeout);
      if (byProfile != null) {
        // Dobbeltsjekk: profil kan være MAVI-ansatt selv om e-post ikke matcher mønsteret.
        final profile = await fetchCurrentUserProfile();
        if (isInternalStaffSession(profile: profile, email: user.email)) {
          return false;
        }
        return true;
      }
      final email = user.email?.trim().toLowerCase() ?? '';
      if (email.isEmpty) return false;
      final byEmail = await client
          .from('partner_portal_accounts')
          .select('id')
          .eq('is_active', true)
          .eq('login_email', email)
          .maybeSingle()
          .timeout(_rpcTimeout);
      return byEmail != null;
    } catch (e) {
      debugPrint('currentSessionHasActivePortalAccount: $e');
      return false;
    }
  }

  static bool _shouldElevateToSuperadmin(UserProfile profile, {String? sessionEmail}) {
    if (_isSuperadminEmail(profile.email) || _isSuperadminEmail(sessionEmail)) {
      return true;
    }
    final no = profile.employeeNumber?.trim();
    if (no != null && no.isNotEmpty && superadminEmployeeNumbers.contains(no)) {
      return true;
    }
    final em = (sessionEmail ?? profile.email)?.trim().toLowerCase() ?? '';
    // Ansatt 25 sitt faste login-alias.
    if (em == 'e25@mavi-employees.driftpro.no') return true;
    return false;
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
    return UserProfile(
      id: u.id,
      email: email,
      fullName: superadminDisplayName,
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
    final isStaff = isInternalStaffSession(email: email);
    final hasPortalAccount =
        !isStaff && await currentSessionHasActivePortalAccount();
    final isPortal = !isStaff && (emailLooksLikePortal(email) || hasPortalAccount);

    if (_isMaviEmployeeEmail(email) || isStaff) {
      try {
        await client.rpc('restore_mavi_employee_profile').timeout(_rpcTimeout);
      } catch (e) {
        debugPrint('restore_mavi_employee_profile: $e');
      }
    } else if (isPortal) {
      try {
        await client.rpc('ensure_partner_profile_from_portal').timeout(_rpcTimeout);
      } catch (e) {
        debugPrint('ensure_partner_profile_from_portal: $e');
      }
    } else {
      await rpcEnsureInternalProfileMissing();
    }

    if (!isStaff && !_isMaviEmployeeEmail(email)) {
      await _silentRpcTimeout('apply_partner_bootstrap_to_profile');
    }

    var profile = await fetchCurrentUserProfile();
    if (profile != null && !isPortal) {
      profile = await _ensureSuperadminIfOwner(profile);
    }

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
        if (profile != null && !isPortal) {
          profile = await _ensureSuperadminIfOwner(profile);
        }
      } catch (e) {
        debugPrint('ensureSessionLinkedToCompany update company_id: $e');
      }
    }

    if (profile == null && !isPortal && _isSuperadminEmail(email) && bootstrap != null) {
      try {
        await client.from('profiles').upsert({
          'id': user.id,
          'email': email,
          'full_name': superadminDisplayName,
          'company_id': bootstrap,
          'role': 'superadmin',
          'is_onboarded': true,
          'is_approved': true,
          'is_active': true,
        }).timeout(_writeTimeout);
        profile = await fetchCurrentUserProfile();
        if (profile != null && !isPortal) {
          profile = await _ensureSuperadminIfOwner(profile);
        }
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

    if (isPortal) return null;

    final recovery = emergencySuperadminProfileFromSession();
    if (recovery == null) return null;
    return bootstrap != null ? recovery.copyWith(companyId: bootstrap) : recovery;
  }

  /// Oppdaterer eller fjerner partner-kobling på profil etter aktiv portal-konto.
  static Future<void> applyPartnerBootstrap() async {
    await _silentRpcTimeout('apply_partner_bootstrap_to_profile');
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
resolver:profiles!resolved_by(full_name),
department:departments!department_id(name)
''';

  static Future<List<Ticket>> fetchTickets({
    String? companyId,
  }) async {
    if (!isConfigured) return const [];

    List<Ticket> parseRows(List<dynamic> data) {
      final out = <Ticket>[];
      for (final e in data) {
        try {
          if (e is Map<String, dynamic>) {
            out.add(Ticket.fromJson(e));
          } else if (e is Map) {
            out.add(Ticket.fromJson(Map<String, dynamic>.from(e)));
          }
        } catch (err) {
          debugPrint('ticket parse skipped: $err');
        }
      }
      return out;
    }

    try {
      dynamic query = client
          .from('tickets')
          .select(ticketSelectEmbed);
      if (companyId != null) {
        query = query.eq('company_id', companyId);
      }
      final data =
          await query.order('created_at', ascending: false) as List<dynamic>;
      return parseRows(data);
    } catch (_) {
      dynamic q2 = client.from('tickets').select();
      if (companyId != null) {
        q2 = q2.eq('company_id', companyId);
      }
      final data = await q2.order('created_at', ascending: false) as List<dynamic>;
      return parseRows(data);
    }
  }

  /// Strengt scoped avviksliste for innlogget bruker:
  /// - ansatt: kun egne
  /// - leder: egne + avdeling
  /// - admin/superadmin: hele bedriften
  static Future<List<Ticket>> fetchScopedTickets({
    required UserProfile profile,
  }) async {
    final cid = profile.companyId;
    if (cid == null) return const [];
    final all = await fetchTickets(companyId: cid);
    final active = all.where((t) => !t.isDeleted).toList();
    if (profile.isAdmin) return active;
    if (profile.role == UserRole.leder) {
      return active
          .where((t) =>
              t.reportedBy == profile.id ||
              t.assignedTo == profile.id ||
              (profile.departmentId != null &&
                  t.departmentId == profile.departmentId))
          .toList();
    }
    return active.where((t) =>
        t.reportedBy == profile.id ||
        (profile.departmentId != null &&
            t.departmentId == profile.departmentId)).toList();
  }

  static Future<List<Ticket>> fetchScopedTicketsIncludingDeleted({
    required UserProfile profile,
  }) async {
    final cid = profile.companyId;
    if (cid == null) return const [];
    final all = await fetchTickets(companyId: cid);
    if (profile.isAdmin) return all;
    return fetchScopedTickets(profile: profile);
  }

  static Future<Ticket> softDeleteTicket({
    required String ticketId,
    required String deletionComment,
  }) async {
    final row = await client.rpc(
      'soft_delete_ticket',
      params: {
        'p_ticket_id': ticketId,
        'p_deletion_comment': deletionComment,
      },
    ) as Map<String, dynamic>;
    return Ticket.fromJson(row);
  }

  static Future<Ticket?> fetchTicketById(String id) async {
    if (!isConfigured) return null;
    Ticket? parse(dynamic row) {
      if (row == null) return null;
      try {
        if (row is Map<String, dynamic>) return Ticket.fromJson(row);
        if (row is Map) {
          return Ticket.fromJson(Map<String, dynamic>.from(row));
        }
      } catch (e) {
        debugPrint('fetchTicketById parse: $e');
      }
      return null;
    }

    try {
      final row = await client
          .from('tickets')
          .select(ticketSelectEmbed)
          .eq('id', id)
          .maybeSingle();
      return parse(row);
    } catch (_) {
      final row =
          await client.from('tickets').select().eq('id', id).maybeSingle();
      return parse(row);
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
    final created = Ticket.fromJson(inserted);
    unawaited(NotificationOutboxService.flushAll());
    return created;
  }

  static Future<List<TicketComment>> fetchTicketComments(String ticketId) async {
    final data = await client
        .from('ticket_comments')
        .select('*, profiles(full_name, avatar_url)')
        .eq('ticket_id', ticketId)
        .order('created_at', ascending: true) as List<dynamic>;
    final out = <TicketComment>[];
    for (final e in data) {
      try {
        if (e is Map<String, dynamic>) {
          out.add(TicketComment.fromJson(e));
        } else if (e is Map) {
          out.add(TicketComment.fromJson(Map<String, dynamic>.from(e)));
        }
      } catch (err) {
        debugPrint('ticket comment parse: $err');
      }
    }
    return out;
  }

  static Future<void> addTicketComment({
    required String ticketId,
    required String comment,
    TicketStatus? newStatus,
    List<String> imageUrls = const [],
    String? resolutionComment,
    String? rootCause,
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
      if (newStatus == TicketStatus.lukket ||
          newStatus == TicketStatus.tiltakUtfort) {
        upd['resolved_at'] = DateTime.now().toIso8601String();
        upd['resolved_by'] = userId;
      }
      if (resolutionComment != null && resolutionComment.trim().isNotEmpty) {
        upd['resolution_comment'] = resolutionComment.trim();
      }
      if (rootCause != null && rootCause.trim().isNotEmpty) {
        upd['root_cause'] = rootCause.trim();
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

  /// Strengt scoped fraværsliste for innlogget bruker:
  /// - ansatt: kun egne
  /// - leder: egne + avdeling
  /// - admin/superadmin: hele bedriften
  static Future<List<Absence>> fetchScopedAbsences({
    required UserProfile profile,
  }) async {
    if (profile.companyId == null) return const [];
    final all = await fetchAbsences(companyId: profile.companyId);
    if (profile.isAdmin) return all;
    if (profile.role == UserRole.leder) {
      return all
          .where((a) =>
              a.userId == profile.id ||
              (profile.departmentId != null &&
                  a.departmentId == profile.departmentId))
          .toList();
    }
    // Ansatt: egne søknader + kollegaers godkjente/ventende fravær i avdelingen (planlegging).
    return all
        .where((a) =>
            a.userId == profile.id ||
            (profile.departmentId != null &&
                a.departmentId == profile.departmentId &&
                a.status != AbsenceStatus.avvist))
        .toList();
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
    try {
      var query = client.from('risk_assessments').select();
      if (companyId != null) query = query.eq('company_id', companyId);
      final data =
          await query.order('created_at', ascending: false) as List<dynamic>;
      return data
          .map((e) => RiskAssessment.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('fetchRiskAssessments: $e');
      return const [];
    }
  }

  static Future<RiskAssessment?> fetchRiskAssessmentById(String id) async {
    if (!isConfigured) return null;
    final row = await client
        .from('risk_assessments')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return RiskAssessment.fromJson(row);
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
    try {
      var query = client.from('sja_forms').select();
      if (companyId != null) query = query.eq('company_id', companyId);
      final data =
          await query.order('created_at', ascending: false) as List<dynamic>;
      return data
          .map((e) => SjaForm.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('fetchSjaForms: $e');
      return const [];
    }
  }

  static Future<SjaForm?> fetchSjaFormById(String id) async {
    if (!isConfigured) return null;
    final row =
        await client.from('sja_forms').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    return SjaForm.fromJson(row);
  }

  static Future<SjaForm> createSjaForm(SjaForm sja) async {
    final data = await client.from('sja_forms').insert(sja.toInsertJson()).select().single();
    return SjaForm.fromJson(data);
  }

  static Future<void> updateSjaStatus(String id, SjaStatus status) async {
    await client.from('sja_forms').update({'status': status.dbValue}).eq('id', id);
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

  /// Avdelinger denne profilen er registrert som leder for.
  static Future<Set<String>> fetchDepartmentIdsLedByProfile(String profileId) async {
    if (!isConfigured) return {};
    try {
      final data = await client
          .from('department_leaders')
          .select('department_id')
          .eq('profile_id', profileId);
      return (data as List)
          .map((r) => r['department_id'] as String)
          .toSet();
    } catch (e) {
      debugPrint('fetchDepartmentIdsLedByProfile: $e');
      return {};
    }
  }

  /// Legg til / fjern én leder på én avdeling (beholder andre ledere).
  static Future<void> setProfileLeadsDepartment({
    required String departmentId,
    required String profileId,
    required bool isLeader,
  }) async {
    final map = await fetchDepartmentLeaderIdsByDepartment([departmentId]);
    final current = List<String>.from(map[departmentId] ?? []);
    if (isLeader) {
      if (!current.contains(profileId)) current.add(profileId);
    } else {
      current.remove(profileId);
    }
    await setDepartmentLeaders(departmentId, current);
  }

  static Future<List<UserProfile>> fetchProfiles({String? companyId, String? departmentId}) async {
    if (!isConfigured) return const [];
    var query = client.from('profiles').select();
    if (companyId != null) query = query.eq('company_id', companyId);
    if (departmentId != null) query = query.eq('department_id', departmentId);
    final data = await query.order('full_name', ascending: true);
    return (data as List).map((e) => UserProfile.fromJson(e)).toList();
  }

  static List<UserProfile> filterMaviEmployees(
    Iterable<UserProfile> profiles, {
    bool requireActive = false,
    bool requireApproved = false,
  }) {
    return profiles
        .where((p) {
          if (!p.isMaviEmployee) return false;
          if (requireActive && !p.isActive) return false;
          if (requireApproved && !p.isApproved) return false;
          return true;
        })
        .toList();
  }

  /// Kun interne MAVI-ansatte — bruk ved deltaker-/ansattvalg (HMS, fravær, osv.).
  static Future<List<UserProfile>> fetchMaviEmployees({
    String? companyId,
    String? departmentId,
    bool requireActive = true,
    bool requireApproved = true,
  }) async {
    final profiles = await fetchProfiles(
      companyId: companyId,
      departmentId: departmentId,
    );
    return filterMaviEmployees(
      profiles,
      requireActive: requireActive,
      requireApproved: requireApproved,
    );
  }

  /// GDPR: ansatt = kun egen profil, leder = egne avdelinger, admin/superadmin = hele bedriften.
  static Future<List<UserProfile>> fetchScopedProfiles(UserProfile viewer) async {
    if (!isConfigured) return const [];
    final companyId = viewer.companyId;
    if (companyId == null) return [viewer];

    if (viewer.role == UserRole.superadmin || viewer.role == UserRole.admin) {
      return fetchProfiles(companyId: companyId);
    }

    if (viewer.role == UserRole.leder) {
      final ledDeptIds = await fetchDepartmentIdsLedByProfile(viewer.id);
      final allowedDeptIds = {...ledDeptIds};
      if (viewer.departmentId != null) {
        allowedDeptIds.add(viewer.departmentId!);
      }
      if (allowedDeptIds.isEmpty) return [viewer];

      final all = await fetchProfiles(companyId: companyId);
      return all
          .where(
            (p) =>
                p.id == viewer.id ||
                (p.departmentId != null && allowedDeptIds.contains(p.departmentId)),
          )
          .toList();
    }

    return [viewer];
  }

  /// Kun superadmin kan administrere ansatte via organisasjonskart / ansattliste.
  static bool canManageEmployees(UserProfile? viewer) =>
      viewer?.role == UserRole.superadmin;

  static TicketAssigneeOptions _parseTicketAssigneeOptionsRpc(dynamic data) {
    if (data is! Map) return const TicketAssigneeOptions();
    List<UserProfile> parseList(dynamic raw) {
      if (raw is! List) return const [];
      final out = <UserProfile>[];
      for (final item in raw) {
        if (item is! Map) continue;
        try {
          out.add(UserProfile.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {}
      }
      return out;
    }
    final map = Map<String, dynamic>.from(data);
    return TicketAssigneeOptions(
      nearestLeaders: parseList(map['nearest_leaders']),
      otherLeaders: parseList(map['other_leaders']),
      superadmins: parseList(map['superadmins']),
    );
  }

  /// Nærmeste leder (avdeling) + superadmin — hvem avsender kan velge.
  static Future<TicketAssigneeOptions> fetchTicketAssigneeOptions({
    required String companyId,
    String? departmentId,
  }) async {
    if (!isConfigured) {
      return const TicketAssigneeOptions();
    }

    try {
      final rpc = await client.rpc(
        'get_ticket_assignee_options',
        params: {
          if (departmentId != null && departmentId.isNotEmpty)
            'p_department_id': departmentId,
        },
      );
      final fromRpc = _parseTicketAssigneeOptionsRpc(rpc);
      if (!fromRpc.isEmpty) return fromRpc;
    } catch (e) {
      debugPrint('get_ticket_assignee_options: $e');
    }

    final deptLeaderIds = <String>[];
    void addDeptLeaderId(String? id) {
      if (id == null || id.isEmpty) return;
      if (!deptLeaderIds.contains(id)) deptLeaderIds.add(id);
    }

    if (departmentId != null && departmentId.isNotEmpty) {
      try {
        final deptRow = await client
            .from('departments')
            .select('leader_id')
            .eq('id', departmentId)
            .maybeSingle();
        addDeptLeaderId(deptRow?['leader_id'] as String?);
      } catch (_) {}
      final map = await fetchDepartmentLeaderIdsByDepartment([departmentId]);
      for (final id in map[departmentId] ?? []) {
        addDeptLeaderId(id);
      }
    }

    final companyProfiles = await fetchProfiles(companyId: companyId);
    bool eligible(UserProfile p) =>
        p.isActive && p.isApproved && !p.isPartnerPortalUser;

    final nearest = <UserProfile>[];
    for (final id in deptLeaderIds) {
      final p = companyProfiles.where((x) => x.id == id).firstOrNull;
      if (p != null && eligible(p)) {
        nearest.add(p);
      }
    }
    if (nearest.isEmpty && departmentId != null) {
      for (final p in companyProfiles) {
        if (eligible(p) &&
            p.role == UserRole.leder &&
            p.departmentId == departmentId) {
          if (!nearest.any((x) => x.id == p.id)) nearest.add(p);
        }
      }
    }
    nearest.sort((a, b) => a.fullName.compareTo(b.fullName));

    final allDepts = await fetchDepartments(companyId: companyId);
    final leaderMap = await fetchDepartmentLeaderIdsByDepartment(
      allDepts.map((d) => d.id).toList(),
    );
    final allLeaderIds = <String>{};
    for (final d in allDepts) {
      if (d.leaderId != null && d.leaderId!.isNotEmpty) {
        allLeaderIds.add(d.leaderId!);
      }
      for (final id in leaderMap[d.id] ?? []) {
        allLeaderIds.add(id);
      }
    }
    for (final p in companyProfiles) {
      if (eligible(p) &&
          (p.role == UserRole.leder || p.role == UserRole.admin)) {
        allLeaderIds.add(p.id);
      }
    }

    final nearestIds = nearest.map((p) => p.id).toSet();
    final otherLeaders = <UserProfile>[];
    for (final id in allLeaderIds) {
      if (nearestIds.contains(id)) continue;
      final p = companyProfiles.where((x) => x.id == id).firstOrNull;
      if (p != null && eligible(p)) otherLeaders.add(p);
    }
    otherLeaders.sort((a, b) => a.fullName.compareTo(b.fullName));

    final usedIds = {
      ...nearestIds,
      ...otherLeaders.map((p) => p.id),
    };
    final superadmins = companyProfiles
        .where(
          (p) =>
              eligible(p) &&
              p.role == UserRole.superadmin &&
              !usedIds.contains(p.id),
        )
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    return TicketAssigneeOptions(
      nearestLeaders: nearest,
      otherLeaders: otherLeaders,
      superadmins: superadmins,
    );
  }

  static Future<Ticket?> fetchTicketByNumber({
    required String companyId,
    required int ticketNumber,
  }) async {
    if (!isConfigured) return null;
    try {
      final row = await client
          .from('tickets')
          .select(ticketSelectEmbed)
          .eq('company_id', companyId)
          .eq('ticket_number', ticketNumber)
          .maybeSingle();
      if (row == null) return null;
      return Ticket.fromJson(row);
    } catch (_) {
      final row = await client
          .from('tickets')
          .select()
          .eq('company_id', companyId)
          .eq('ticket_number', ticketNumber)
          .maybeSingle();
      if (row == null) return null;
      return Ticket.fromJson(row);
    }
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

    final email = user.email?.trim().toLowerCase() ?? '';
    if (_isMaviEmployeeEmail(email) || isInternalStaffSession(email: email)) {
      try {
        await client.rpc('restore_mavi_employee_profile').timeout(_rpcTimeout);
      } catch (e) {
        debugPrint('restore_mavi_employee_profile: $e');
      }
    } else {
      await _silentRpcTimeout('apply_partner_bootstrap_to_profile');
    }

    var existing = await fetchCurrentUserProfile();
    if (existing == null &&
        !_isMaviEmployeeEmail(email) &&
        !isInternalStaffSession(email: email)) {
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
      existing = await fetchCurrentUserProfile() ?? existing;
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
      final email = user.email?.trim().toLowerCase() ?? '';
      String fullName = _isSuperadminEmail(email)
          ? superadminDisplayName
          : (user.userMetadata?['full_name']?.toString() ??
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

  /// Løfter eier-e-post / ansatt 25 til superadmin. Rydder eventuell partner-blanding.
  static Future<UserProfile> _ensureSuperadminIfOwner(UserProfile profile) async {
    final sessionEmail = currentUser?.email;
    // Ren portal-e-post uten MAVI-/eier-identitet → ikke rør.
    if (emailLooksLikePortal(sessionEmail) &&
        !isInternalStaffSession(profile: profile, email: sessionEmail)) {
      return profile;
    }
    if (!_shouldElevateToSuperadmin(profile, sessionEmail: sessionEmail)) {
      return profile;
    }
    final needsNameFix = profile.fullName.trim() != superadminDisplayName;
    final needsPartnerClear =
        profile.partnerId != null ||
        profile.partnerVehicleId != null ||
        profile.role == UserRole.samarbeidspartner;
    if (profile.role == UserRole.superadmin &&
        profile.isApproved &&
        profile.isOnboarded &&
        !needsNameFix &&
        !needsPartnerClear) {
      return profile;
    }
    try {
      await client
          .from('profiles')
          .update({
            'role': 'superadmin',
            'full_name': superadminDisplayName,
            'partner_id': null,
            'partner_vehicle_id': null,
            'is_approved': true,
            'is_onboarded': true,
            'is_active': true,
          })
          .eq('id', profile.id)
          .timeout(_writeTimeout);
      // Løsne portal-konto fra denne profilen (portal beholder egen innlogging).
      try {
        await client
            .from('partner_portal_accounts')
            .update({'profile_id': null})
            .eq('profile_id', profile.id)
            .eq('is_active', true)
            .timeout(_writeTimeout);
      } catch (e) {
        debugPrint('unlink partner_portal_accounts profile_id: $e');
      }
      final refreshed = await fetchCurrentUserProfile();
      return refreshed ??
          profile.copyWith(
            role: UserRole.superadmin,
            fullName: superadminDisplayName,
            partnerId: null,
            partnerVehicleId: null,
            isApproved: true,
            isOnboarded: true,
            isActive: true,
          );
    } catch (e) {
      debugPrint('ensureSuperadminIfOwner: $e');
      return profile.copyWith(
        role: UserRole.superadmin,
        fullName: superadminDisplayName,
        partnerId: null,
        partnerVehicleId: null,
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
    String? nationalIdNumber,
    DateTime? hireDate,
    int? childrenUnder12Count,
    String? emergencyContactName,
    String? emergencyContactPhone,
    bool? isSafetyRepresentative,
    bool? isActive,
    bool? smsOptIn,
    bool? emailOptIn,
    String? notifyChannelPreference,
    bool clearBirthDate = false,
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
    if (clearBirthDate) {
      patch['birth_date'] = null;
    } else if (birthDate != null) {
      patch['birth_date'] = birthDate.toIso8601String().split('T').first;
    }
    if (nationalIdNumber != null) {
      patch['national_id_number'] = NorwegianNationalId.normalize(nationalIdNumber);
    }
    if (hireDate != null) {
      patch['hire_date'] = hireDate.toIso8601String().split('T').first;
    }
    if (childrenUnder12Count != null) {
      patch['children_under_12_count'] =
          childrenUnder12Count.clamp(0, 12);
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
    if (emailOptIn != null) patch['email_opt_in'] = emailOptIn;
    if (notifyChannelPreference != null) {
      patch['notify_channel_preference'] = notifyChannelPreference;
    }
    if (patch.isEmpty) return;
    await client.from('profiles').update(patch).eq('id', profileId);
  }

  /// Ansatt oppdaterer antall barn under 12 på egen profil.
  static Future<void> updateProfileChildrenUnder12({
    required String profileId,
    required int count,
  }) async {
    final user = client.auth.currentUser;
    if (user == null || user.id != profileId) {
      throw StateError('Kan bare oppdatere egen profil');
    }
    await client.from('profiles').update({
      'children_under_12_count': count.clamp(0, 12),
    }).eq('id', profileId);
  }

  /// Endrer innloggings- og varsel-e-post (kun superadmin via Edge Function).
  static Future<String> updateEmployeeEmail({
    required String profileId,
    required String newEmail,
  }) async {
    final token = client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Økten er utløpt. Logg inn på nytt.');
    }
    final normalized = newEmail.trim().toLowerCase();
    final res = await client.functions.invoke(
      'update-employee-email',
      body: {
        'profile_id': profileId,
        'new_email': normalized,
      },
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception('${data['error']}');
    }
    if (res.status >= 400) {
      throw Exception('Kunne ikke oppdatere e-post (${res.status})');
    }
    if (data is Map && data['email'] is String) {
      return data['email'] as String;
    }
    return normalized;
  }

  /// Oppretter intern ansatt via Edge Function (auth.users + profiles + feriekvote).
  static Future<UserProfile> createEmployeeProfile({
    required String companyId,
    required String fullName,
    String? departmentId,
    String? jobTitle,
    UserRole role = UserRole.ansatt,
  }) async {
    final token = client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Økten er utløpt. Logg inn på nytt.');
    }
    final res = await client.functions.invoke(
      'create-internal-employee',
      body: {
        'company_id': companyId,
        'full_name': fullName.trim(),
        'department_id': departmentId,
        'job_title': jobTitle?.trim().isEmpty == true ? null : jobTitle?.trim(),
        'role': role.name,
      },
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception('${data['error']}');
    }
    final profile = data is Map ? data['profile'] : null;
    if (profile is Map<String, dynamic>) {
      return UserProfile.fromJson(profile);
    }
    if (profile is Map) {
      return UserProfile.fromJson(Map<String, dynamic>.from(profile));
    }
    throw StateError('Kunne ikke opprette ansatt i Supabase.');
  }

  /// Deaktiverer ansatt (beholder historikk). Ledere: egen avdeling. Admin: hele selskapet.
  static Future<void> deactivateEmployeeProfile(String profileId) async {
    await client.rpc('deactivate_employee_profile', params: {
      'p_profile_id': profileId,
    });
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

  /// App Store: slett egen konto (edge `delete-own-account`).
  static Future<void> deleteOwnAccount() async {
    final token = client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Økten er utløpt. Logg inn på nytt.');
    }
    final res = await client.functions.invoke(
      'delete-own-account',
      body: {'confirm': 'SLETT'},
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception('${data['error']}');
    }
  }

  static Future<String?> getCurrentCompanyId() async {
    try {
      if (SupabaseConfig.defaultCompanyId != null) {
        return SupabaseConfig.defaultCompanyId;
      }

      final profile = await ensureSessionLinkedToCompany();

      try {
        final rpc = await client.rpc('get_user_company_id').timeout(_rpcTimeout);
        if (rpc is String && rpc.isNotEmpty) return rpc;
      } catch (_) {}

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
