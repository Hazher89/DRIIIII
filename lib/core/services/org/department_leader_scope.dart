import '../../../models/absence.dart';
import '../../../models/ticket.dart';
import '../../../models/user_profile.dart';
import '../../permissions/user_access.dart';
import '../supabase_service.dart';

/// Avdelingsleder-scope: hvilke avdelinger en profil leder og hva de skal se.
abstract final class DepartmentLeaderScope {
  static Future<Set<String>> ledDepartmentIds(String profileId) =>
      SupabaseService.fetchDepartmentIdsLedByProfile(profileId);

  static Future<Set<String>> managedDepartmentIds(UserProfile profile) async {
    final out = <String>{...await ledDepartmentIds(profile.id)};

    final companyId = profile.companyId;
    if (companyId != null && companyId.isNotEmpty) {
      final depts = await SupabaseService.fetchDepartments(companyId: companyId);
      for (final d in depts) {
        if (d.leaderId == profile.id || d.leaderIds.contains(profile.id)) {
          out.add(d.id);
        }
      }
    }

    if (profile.role == UserRole.leder &&
        profile.departmentId != null &&
        profile.departmentId!.isNotEmpty) {
      out.add(profile.departmentId!);
    }
    return out;
  }

  static Future<bool> leadsAnyDepartment(String profileId) async {
    final ids = await ledDepartmentIds(profileId);
    return ids.isNotEmpty;
  }

  static Future<bool> canManageTeam(UserProfile profile) async {
    if (profile.isAdmin) return true;
    if (profile.access.canApproveLeave ||
        profile.access.canRegisterLeaveForOthers) {
      return true;
    }
    if (profile.role == UserRole.leder) return true;
    if (await leadsAnyDepartment(profile.id)) return true;

    final companyId = profile.companyId;
    if (companyId == null || companyId.isEmpty) return false;
    final depts = await SupabaseService.fetchDepartments(companyId: companyId);
    return depts.any(
      (d) => d.leaderId == profile.id || d.leaderIds.contains(profile.id),
    );
  }

  static bool absenceInScope(
    Absence absence,
    UserProfile profile,
    Set<String> departmentIds,
  ) {
    if (absence.userId == profile.id) return true;
    final dept = absence.departmentId;
    return dept != null && departmentIds.contains(dept);
  }

  static bool ticketInScope(
    Ticket ticket,
    UserProfile profile,
    Set<String> departmentIds,
  ) {
    if (ticket.reportedBy == profile.id || ticket.assignedTo == profile.id) {
      return true;
    }
    final dept = ticket.departmentId;
    return dept != null && departmentIds.contains(dept);
  }
}
