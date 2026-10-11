import '../../models/ticket_assignee_options.dart';
import '../../models/user_profile.dart';
import '../constants/company_principals.dart';

/// Ledelsestrekk: ansatt → avdelingsleder → Hazher (driftsleder) → Tommy (daglig leder).
class LeadershipChain {
  LeadershipChain._();

  static List<UserProfile> directManagers({
    required UserProfile subject,
    required TicketAssigneeOptions options,
    bool honorOverride = true,
  }) {
    final pool = <UserProfile>[
      ...options.nearestLeaders,
      ...options.otherLeaders,
      ...options.superadmins,
    ];

    UserProfile? findId(String id) {
      for (final person in pool) {
        if (person.id == id) return person;
      }
      return null;
    }

    UserProfile? findPrincipal(CompanyPrincipal principal) {
      for (final person in pool) {
        if (person.id == subject.id) continue;
        if (CompanyPrincipal.ofProfile(person) == principal) return person;
      }
      return null;
    }

    final override = honorOverride ? subject.reportsTo : null;
    if (override != null && override.isNotEmpty && override != subject.id) {
      final chosen = findId(override);
      if (chosen != null) return [chosen];
    }

    final tier = CompanyPrincipal.ofProfile(subject);
    if (tier == CompanyPrincipal.tommy || tier == CompanyPrincipal.nico) {
      return const [];
    }
    if (tier == CompanyPrincipal.hazher) {
      final tommy = findPrincipal(CompanyPrincipal.tommy);
      return tommy == null ? const [] : [tommy];
    }

    final aboveDepartment = options.nearestLeaders
        .where((person) => person.id != subject.id)
        .toList();
    final isDepartmentLeader =
        options.nearestLeaders.any((person) => person.id == subject.id);
    if (isDepartmentLeader) {
      final hazher = findPrincipal(CompanyPrincipal.hazher);
      if (hazher != null) return [hazher];
      return aboveDepartment;
    }
    if (aboveDepartment.isNotEmpty) return aboveDepartment;

    final hazher = findPrincipal(CompanyPrincipal.hazher);
    if (hazher != null) return [hazher];
    return options.superadmins.where((person) => person.id != subject.id).toList();
  }

  static TicketAssigneeOptions apply({
    required UserProfile subject,
    required TicketAssigneeOptions options,
  }) {
    final managers = directManagers(subject: subject, options: options);
    final managerIds = managers.map((person) => person.id).toSet();
    bool keep(UserProfile person) =>
        person.id != subject.id && !managerIds.contains(person.id);
    return TicketAssigneeOptions(
      nearestLeaders: managers,
      otherLeaders: options.otherLeaders.where(keep).toList(),
      superadmins: options.superadmins.where(keep).toList(),
    );
  }
}
