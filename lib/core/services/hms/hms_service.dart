import '../../../models/hms/equipment.dart';
import '../../../models/risk_assessment.dart';
import '../../../models/sja_form.dart';
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
}

class HmsService {
  HmsService._();

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

    return HmsDashboardStats(
      riskCount: risks.length,
      highRiskCount: risks.where((r) => r.isHighRisk).length,
      sjaOpen: sjas
          .where((s) =>
              s.status == SjaStatus.utkast || s.status == SjaStatus.signert)
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
