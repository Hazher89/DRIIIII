import '../../models/user_profile.dart';

/// Faste eiere/ledere i MAVI — visningstittel overalt (aldri «admin»/«superadmin»).
///
/// Hierarki:
/// - [tommy] + [nico] = samme nivå (topp)
/// - [hazher] = under dem (driftsleder)
/// - avdelingsledere = under Hazher
enum CompanyPrincipal {
  tommy(
    displayName: 'Tommy Larsen',
    title: 'Daglig leder & medeier',
    employeeNumbers: {'100'},
    nameNeedles: ['tommy larsen', 'tommy'],
    emailNeedles: ['tommy'],
    sortOrder: 0,
    hierarchyLevel: 0,
  ),
  nico(
    displayName: 'Nicola Vino',
    title: 'Medeier',
    employeeNumbers: {'144'},
    nameNeedles: ['nicola vino', 'nicola', 'nico'],
    emailNeedles: ['nico', 'nicola'],
    sortOrder: 1,
    hierarchyLevel: 0,
  ),
  hazher(
    displayName: 'Hazher Abdullah',
    title: 'Driftsleder',
    employeeNumbers: {'25'},
    nameNeedles: ['hazher abdullah', 'hazher'],
    emailNeedles: ['hazher', 'baxigshti', 'baxightsi', 'baxlgshtl'],
    sortOrder: 2,
    hierarchyLevel: 1,
  );

  const CompanyPrincipal({
    required this.displayName,
    required this.title,
    required this.employeeNumbers,
    required this.nameNeedles,
    required this.emailNeedles,
    required this.sortOrder,
    required this.hierarchyLevel,
  });

  final String displayName;
  final String title;
  final Set<String> employeeNumbers;
  final List<String> nameNeedles;
  final List<String> emailNeedles;
  final int sortOrder;

  /// 0 = Tommy/Nico (topp), 1 = Hazher (under).
  final int hierarchyLevel;

  bool get isOwnerLevel => hierarchyLevel == 0;
  bool get isOperationsLevel => hierarchyLevel == 1;

  static const allEmployeeNumbers = {'100', '144', '25'};

  static CompanyPrincipal? match({
    String? fullName,
    String? email,
    String? employeeNumber,
  }) {
    final en = employeeNumber?.trim();
    if (en != null && en.isNotEmpty) {
      for (final p in values) {
        if (p.employeeNumbers.contains(en)) return p;
      }
    }

    final em = (email ?? '').trim().toLowerCase();
    if (em.isNotEmpty) {
      for (final p in values) {
        for (final needle in p.emailNeedles) {
          if (em.contains(needle)) return p;
        }
      }
    }

    final name = (fullName ?? '').trim().toLowerCase();
    if (name.isEmpty) return null;

    final scored = <({CompanyPrincipal principal, String needle})>[];
    for (final p in values) {
      for (final needle in p.nameNeedles) {
        scored.add((principal: p, needle: needle));
      }
    }
    scored.sort((a, b) => b.needle.length.compareTo(a.needle.length));
    for (final s in scored) {
      if (name == s.needle || name.contains(s.needle)) return s.principal;
    }
    return null;
  }

  static CompanyPrincipal? ofProfile(UserProfile profile) => match(
        fullName: profile.fullName,
        email: profile.email,
        employeeNumber: profile.employeeNumber,
      );

  static bool isPrincipal(UserProfile profile) => ofProfile(profile) != null;

  static bool isOwner(UserProfile profile) =>
      ofProfile(profile)?.isOwnerLevel == true;

  static bool isOperations(UserProfile profile) =>
      ofProfile(profile)?.isOperationsLevel == true;
}

/// Vennlige rolle-/titteltekster for UI (partner + MAVI).
extension UserProfileDisplayTitle on UserProfile {
  String get displayTitle {
    final principal = CompanyPrincipal.ofProfile(this);
    if (principal != null) return principal.title;

    final jt = jobTitle?.trim();
    if (jt != null && jt.isNotEmpty && !_looksLikeSystemRole(jt)) {
      return jt;
    }
    return displayRoleLabel;
  }

  String get displayRoleLabel {
    final principal = CompanyPrincipal.ofProfile(this);
    if (principal != null) return principal.title;
    final badges = <String>[];
    if (isChiefSafetyRepresentative) {
      badges.add('Hovedverneombud');
    } else if (isSafetyRepresentative) {
      badges.add('Verneombud');
    }
    if (isUnionRepresentative) badges.add('Tillitsvalgt');
    if (isAmuMember) badges.add('AMU');
    final base = switch (role) {
      UserRole.superadmin => 'DriftPro',
      UserRole.admin => 'Administrator',
      UserRole.leder => 'Avdelingsleder',
      UserRole.ansatt => 'Ansatt',
      UserRole.samarbeidspartner => 'Samarbeidspartner',
    };
    if (badges.isEmpty) return base;
    return '$base · ${badges.join(' · ')}';
  }
}

bool _looksLikeSystemRole(String value) {
  final v = value.trim().toLowerCase();
  return v == 'superadmin' ||
      v == 'admin' ||
      v == 'administrator' ||
      v == 'leder' ||
      v == 'ansatt';
}
