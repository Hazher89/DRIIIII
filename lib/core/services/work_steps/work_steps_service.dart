import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/supabase_service.dart';
import 'work_steps_privacy.dart';

class WorkStepsSettings {
  const WorkStepsSettings({
    required this.companyId,
    this.enabled = true,
    this.workplaceName = 'Arbeidssted',
    this.workplaceLat,
    this.workplaceLng,
    this.radiusMeters = 200,
  });

  final String companyId;
  final bool enabled;
  final String workplaceName;
  final double? workplaceLat;
  final double? workplaceLng;
  final int radiusMeters;

  bool get hasWorkplace =>
      workplaceLat != null && workplaceLng != null;

  factory WorkStepsSettings.fromJson(Map<String, dynamic> json) {
    return WorkStepsSettings(
      companyId: json['company_id']?.toString() ?? '',
      enabled: json['enabled'] != false,
      workplaceName:
          (json['workplace_name'] as String?)?.trim().isNotEmpty == true
              ? (json['workplace_name'] as String).trim()
              : 'Arbeidssted',
      workplaceLat: (json['workplace_lat'] as num?)?.toDouble(),
      workplaceLng: (json['workplace_lng'] as num?)?.toDouble(),
      radiusMeters: (json['radius_meters'] as num?)?.toInt() ?? 200,
    );
  }

  Map<String, dynamic> toUpsertJson() => {
        'company_id': companyId,
        'enabled': enabled,
        'workplace_name': workplaceName,
        'workplace_lat': workplaceLat,
        'workplace_lng': workplaceLng,
        'radius_meters': radiusMeters.clamp(50, 2000),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}

class WorkStepsConsent {
  const WorkStepsConsent({
    required this.profileId,
    required this.companyId,
    this.enabled = false,
    this.consentVersion = kWorkStepsConsentVersion,
    this.consentedAt,
    this.revokedAt,
  });

  final String profileId;
  final String companyId;
  final bool enabled;
  final String consentVersion;
  final DateTime? consentedAt;
  final DateTime? revokedAt;

  factory WorkStepsConsent.fromJson(Map<String, dynamic> json) {
    return WorkStepsConsent(
      profileId: json['profile_id']?.toString() ?? '',
      companyId: json['company_id']?.toString() ?? '',
      enabled: json['enabled'] == true,
      consentVersion:
          (json['consent_version'] as String?) ?? kWorkStepsConsentVersion,
      consentedAt: json['consented_at'] != null
          ? DateTime.tryParse(json['consented_at'].toString())
          : null,
      revokedAt: json['revoked_at'] != null
          ? DateTime.tryParse(json['revoked_at'].toString())
          : null,
    );
  }
}

class WorkStepsDaily {
  const WorkStepsDaily({
    required this.workDate,
    required this.stepsAtWork,
    this.syncedAt,
    this.atWorkplace = true,
  });

  final DateTime workDate;
  final int stepsAtWork;
  final DateTime? syncedAt;
  final bool atWorkplace;

  factory WorkStepsDaily.fromJson(Map<String, dynamic> json) {
    return WorkStepsDaily(
      workDate: DateTime.tryParse(json['work_date'].toString()) ??
          DateTime.now(),
      stepsAtWork: (json['steps_at_work'] as num?)?.toInt() ?? 0,
      syncedAt: json['synced_at'] != null
          ? DateTime.tryParse(json['synced_at'].toString())
          : null,
      atWorkplace: json['at_workplace'] != false,
    );
  }
}

class WorkStepsHubRow {
  const WorkStepsHubRow({
    required this.profileId,
    required this.fullName,
    this.employeeNumber,
    required this.consentEnabled,
    required this.stepsToday,
    required this.stepsPeriod,
    required this.daysWithData,
    this.lastSyncedAt,
  });

  final String profileId;
  final String fullName;
  final String? employeeNumber;
  final bool consentEnabled;
  final int stepsToday;
  final int stepsPeriod;
  final int daysWithData;
  final DateTime? lastSyncedAt;

  factory WorkStepsHubRow.fromJson(Map<String, dynamic> json) {
    return WorkStepsHubRow(
      profileId: json['profile_id']?.toString() ?? '',
      fullName: (json['full_name'] as String?)?.trim() ?? 'Ukjent',
      employeeNumber: (json['employee_number'] as String?)?.trim(),
      consentEnabled: json['consent_enabled'] == true,
      stepsToday: (json['steps_today'] as num?)?.toInt() ?? 0,
      stepsPeriod: (json['steps_period'] as num?)?.toInt() ?? 0,
      daysWithData: (json['days_with_data'] as num?)?.toInt() ?? 0,
      lastSyncedAt: json['last_synced_at'] != null
          ? DateTime.tryParse(json['last_synced_at'].toString())
          : null,
    );
  }
}

/// Database + samtykke for skritt på jobb (uten HealthKit-kall).
class WorkStepsService {
  WorkStepsService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<WorkStepsSettings?> fetchSettings() async {
    final companyId = await SupabaseService.getCurrentCompanyId();
    if (companyId == null) return null;
    final res = await _client
        .from('company_work_steps_settings')
        .select()
        .eq('company_id', companyId)
        .maybeSingle();
    if (res == null) {
      return WorkStepsSettings(companyId: companyId);
    }
    return WorkStepsSettings.fromJson(Map<String, dynamic>.from(res));
  }

  static Future<void> saveSettings(WorkStepsSettings settings) async {
    final uid = _client.auth.currentUser?.id;
    await _client.from('company_work_steps_settings').upsert({
      ...settings.toUpsertJson(),
      if (uid != null) 'updated_by': uid,
    });
  }

  static Future<WorkStepsConsent?> fetchMyConsent() async {
    final uid = _client.auth.currentUser?.id;
    final companyId = await SupabaseService.getCurrentCompanyId();
    if (uid == null || companyId == null) return null;
    final res = await _client
        .from('employee_work_steps_consent')
        .select()
        .eq('profile_id', uid)
        .maybeSingle();
    if (res == null) {
      return WorkStepsConsent(profileId: uid, companyId: companyId);
    }
    return WorkStepsConsent.fromJson(Map<String, dynamic>.from(res));
  }

  static Future<void> setConsentEnabled(bool enabled) async {
    final uid = _client.auth.currentUser?.id;
    final companyId = await SupabaseService.getCurrentCompanyId();
    if (uid == null || companyId == null) {
      throw Exception('Ikke innlogget');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('employee_work_steps_consent').upsert({
      'profile_id': uid,
      'company_id': companyId,
      'enabled': enabled,
      'consent_version': kWorkStepsConsentVersion,
      'consented_at': enabled ? now : null,
      'revoked_at': enabled ? null : now,
      'updated_at': now,
    });
  }

  static Future<List<WorkStepsDaily>> fetchMyHistory({int days = 14}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final from = DateTime.now()
        .toUtc()
        .subtract(Duration(days: days))
        .toIso8601String()
        .substring(0, 10);
    final res = await _client
        .from('employee_work_steps_daily')
        .select()
        .eq('profile_id', uid)
        .gte('work_date', from)
        .order('work_date', ascending: false);
    return (res as List)
        .whereType<Map>()
        .map((e) => WorkStepsDaily.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<void> upsertTodaySteps({
    required int steps,
    required bool atWorkplace,
  }) async {
    final uid = _client.auth.currentUser?.id;
    final companyId = await SupabaseService.getCurrentCompanyId();
    if (uid == null || companyId == null) {
      throw Exception('Ikke innlogget');
    }
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    await _client.from('employee_work_steps_daily').upsert({
      'company_id': companyId,
      'profile_id': uid,
      'work_date': today,
      'steps_at_work': steps.clamp(0, 200000),
      'synced_at': DateTime.now().toUtc().toIso8601String(),
      'at_workplace': atWorkplace,
      'source': 'health_kit_or_health_connect',
    }, onConflict: 'profile_id,work_date');
  }

  static Future<void> deleteMyStepData() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    await _client
        .from('employee_work_steps_daily')
        .delete()
        .eq('profile_id', uid);
  }

  static Future<List<WorkStepsHubRow>> fetchHubOverview({
    DateTime? from,
    DateTime? to,
  }) async {
    final f = (from ?? DateTime.now().subtract(const Duration(days: 14)))
        .toIso8601String()
        .substring(0, 10);
    final t = (to ?? DateTime.now()).toIso8601String().substring(0, 10);
    final res = await _client.rpc(
      'get_work_steps_hub_overview',
      params: {'p_from': f, 'p_to': t},
    );
    if (res is! List) return const [];
    return res
        .whereType<Map>()
        .map((e) => WorkStepsHubRow.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
