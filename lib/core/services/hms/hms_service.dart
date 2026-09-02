import '../../../models/hms/equipment.dart';
import '../../../models/risk_assessment.dart';
import '../../../models/risk_assessment_status.dart';
import '../../../models/sja_form.dart';
import '../../../models/user_profile.dart';
import '../../permissions/user_access.dart';
import 'equipment_service.dart';
import '../supabase_service.dart';

/// Aggregert HMS-status for hub og dashboard.
class HmsDashboardStats {
  final int riskCount;
  final int highRiskCount;
  final int sjaOpen;
  final int safetyPlanned;
  final int equipmentNeedsService;
  final int expiringCertificates;

  const HmsDashboardStats({
    this.riskCount = 0,
    this.highRiskCount = 0,
    this.sjaOpen = 0,
    this.safetyPlanned = 0,
    this.equipmentNeedsService = 0,
    this.expiringCertificates = 0,
  });

  /// Sum av åpne HMS-oppgaver for navigasjons-badge.
  int get navBadgeTotal => riskCount + sjaOpen + safetyPlanned;

  static const zero = HmsDashboardStats();
}

class HmsService {
  HmsService._();

  /// Badge-tall per bruker — kun moduler brukeren har tilgang til (RLS-scopet).
  static Future<int> loadNavBadgeTotal(UserProfile profile) async {
    final access = profile.access;
    final companyId = profile.companyId;
    if (companyId == null || companyId.isEmpty || !access.canHms) return 0;

    var total = 0;

    if (access.canHmsRisk) {
      final risks = await SupabaseService.fetchRiskAssessments(companyId: companyId);
      total += risks.where((r) => RiskAssessmentStatuses.isOpen(r.status)).length;
    }

    if (access.canHmsSja) {
      final sjas = await SupabaseService.fetchSjaForms(companyId: companyId);
      total += sjas
          .where((s) =>
              s.status == SjaStatus.utkast ||
              s.status == SjaStatus.venterSignatur ||
              s.status == SjaStatus.iGang)
          .length;
    }

    if (access.canHmsSafetyRound) {
      final rounds = await SupabaseService.fetchSafetyRounds(companyId: companyId);
      total += rounds.where((r) => r.overallStatus == 'planlagt').length;
    }

    return total;
  }

  static Future<HmsDashboardStats> loadDashboardStats(String companyId) async {
    final risks = await SupabaseService.fetchRiskAssessments(companyId: companyId);
    final sjas = await SupabaseService.fetchSjaForms(companyId: companyId);
    final rounds = await SupabaseService.fetchSafetyRounds(companyId: companyId);

    var equipService = 0;
    try {
      final eq = await EquipmentService.fetchAll(companyId: companyId);
      equipService = eq.where((e) => e.status == EquipmentStatus.needsService).length;
    } catch (_) {}

    var expiring = 0;
    try {
      final docs = await SupabaseService.fetchHmsDocuments(companyId: companyId);
      final now = DateTime.now();
      final limit = now.add(const Duration(days: 60));
      expiring = docs.where((d) {
        final ex = d.expiresAt;
        return ex != null && ex.isBefore(limit) && ex.isAfter(now);
      }).length;
    } catch (_) {}

    final openRisks = risks
        .where((r) => RiskAssessmentStatuses.isOpen(r.status))
        .toList();

    return HmsDashboardStats(
      riskCount: openRisks.length,
      highRiskCount: openRisks.where((r) => r.isHighRisk).length,
      sjaOpen: sjas
          .where((s) =>
              s.status == SjaStatus.utkast ||
              s.status == SjaStatus.venterSignatur ||
              s.status == SjaStatus.iGang)
          .length,
      safetyPlanned: rounds.where((r) => r.overallStatus == 'planlagt').length,
      equipmentNeedsService: equipService,
      expiringCertificates: expiring,
    );
  }

  /// Risiko fordelt på 5×5 (probability × consequence).
  static Map<int, Map<int, int>> riskHeatmap(List<RiskAssessment> risks) {
    final grid = {
      for (var p = 1; p <= 5; p++) p: {for (var c = 1; c <= 5; c++) c: 0},
    };
    for (final r in risks) {
      final p = r.probability.clamp(1, 5);
      final c = r.consequence.clamp(1, 5);
      grid[p]![c] = (grid[p]![c] ?? 0) + 1;
    }
    return grid;
  }
}
