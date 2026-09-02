import '../../../models/user_profile.dart';
import '../../constants/company_principals.dart';
import '../org/department_leader_scope.dart';

/// GDPR-aware tilgang for DriftPro-assistenten.
enum AssistantAccessTier {
  /// Tommy / Nico / Hazher (eller full admin) — alt i bedriften.
  principal,

  /// Avdelingsleder — kun egne avdelinger.
  departmentLeader,

  /// Vanlig ansatt — kun egne persondata.
  selfOnly,
}

class AssistantAccessDecision {
  const AssistantAccessDecision({
    required this.allowed,
    this.reason,
  });

  final bool allowed;
  final String? reason;

  static const allow = AssistantAccessDecision(allowed: true);

  static AssistantAccessDecision deny(String reason) =>
      AssistantAccessDecision(allowed: false, reason: reason);

  static const denyOutOfDepartment = AssistantAccessDecision(
    allowed: false,
    reason:
        'Beklager — jeg kan ikke vise dette. Personen er ikke under din avdeling. '
        'Av personvern (GDPR) får du kun se fravær og statistikk for ansatte du leder.',
  );
}

class AssistantAccessPolicy {
  AssistantAccessPolicy._();

  static Future<AssistantAccessTier> tierFor(UserProfile viewer) async {
    if (CompanyPrincipal.isPrincipal(viewer) || viewer.isAdmin) {
      return AssistantAccessTier.principal;
    }
    if (await DepartmentLeaderScope.canManageTeam(viewer)) {
      return AssistantAccessTier.departmentLeader;
    }
    return AssistantAccessTier.selfOnly;
  }

  /// Kan [viewer] se fravær/statistikk for [subject]?
  static Future<AssistantAccessDecision> canViewEmployeeLeave({
    required UserProfile viewer,
    required UserProfile subject,
  }) async {
    if (viewer.id == subject.id) return AssistantAccessDecision.allow;

    final tier = await tierFor(viewer);
    switch (tier) {
      case AssistantAccessTier.principal:
        return AssistantAccessDecision.allow;
      case AssistantAccessTier.departmentLeader:
        final depts = await DepartmentLeaderScope.managedDepartmentIds(viewer);
        final subjectDept = subject.departmentId;
        if (subjectDept != null && depts.contains(subjectDept)) {
          return AssistantAccessDecision.allow;
        }
        return AssistantAccessDecision.denyOutOfDepartment;
      case AssistantAccessTier.selfOnly:
        return AssistantAccessDecision.deny(
          'Beklager — du kan bare spørre om ditt eget fravær og ferie. '
          'Spør lederen din hvis du trenger oversikt over andre.',
        );
    }
  }

  static Future<bool> canViewFleetOps(UserProfile viewer) async {
    // Rutedata er driftsinfo for bedriften — tilgjengelig for innloggede MAVI-brukere.
    // Personsensitive fraværsdata går via [canViewEmployeeLeave].
    return viewer.companyId != null && viewer.companyId!.isNotEmpty;
  }
}
