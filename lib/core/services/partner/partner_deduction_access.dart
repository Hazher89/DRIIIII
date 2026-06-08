import '../../../models/user_profile.dart';

/// Tilgang til arkiv/fakturering og lås/slett i Bot/Trekk.
abstract final class PartnerDeductionAccess {
  static const _lockManagerEmployeeNumbers = {'25', '100', '144'};

  static bool _matchesLockManager(UserProfile profile) {
    final en = profile.employeeNumber?.trim();
    if (en != null && _lockManagerEmployeeNumbers.contains(en)) return true;
    final name = profile.fullName.toLowerCase();
    final email = profile.email.toLowerCase();
    if (name.contains('tommy') || name.contains('hazher')) return true;
    if (name.contains('nicola') || name.contains('nico')) return true;
    if (email.contains('tommy') || email.contains('hazher')) return true;
    if (email.contains('nico') || email.contains('nicola')) return true;
    return false;
  }

  /// Marker som fakturert — Nico / superadmin.
  static bool canManageArchive(UserProfile? profile) {
    if (profile == null) return false;
    if (profile.role == UserRole.superadmin) return true;
    return _matchesNico(profile);
  }

  /// Lås opp fakturerte saker og soft-slett — kun Nico, Tommy og Hazher.
  static bool canUnlockAndDelete(UserProfile? profile) {
    if (profile == null) return false;
    return _matchesLockManager(profile);
  }

  static bool _matchesNico(UserProfile profile) {
    final en = profile.employeeNumber?.trim();
    if (en == '144') return true;
    final name = profile.fullName.toLowerCase();
    final email = profile.email.toLowerCase();
    return name.contains('nicola') ||
        name.contains('nico') ||
        email.contains('nico') ||
        email.contains('nicola');
  }
}
