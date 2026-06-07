import 'user_profile.dart';

/// Hvem avsender kan velge ved innrapportering av avvik.
class TicketAssigneeOptions {
  /// Avdelingsleder(e) — anbefalt standardvalg for ansattens avdeling.
  final List<UserProfile> nearestLeaders;

  /// Øvrige ledere i bedriften (andre avdelinger).
  final List<UserProfile> otherLeaders;

  /// Sentral eskalering (superadmin).
  final List<UserProfile> superadmins;

  const TicketAssigneeOptions({
    this.nearestLeaders = const [],
    this.otherLeaders = const [],
    this.superadmins = const [],
  });

  bool get isEmpty =>
      nearestLeaders.isEmpty && otherLeaders.isEmpty && superadmins.isEmpty;

  /// Standardvalg: første nærmeste leder, ellers første annen leder, ellers superadmin.
  String? get defaultAssigneeId {
    if (nearestLeaders.isNotEmpty) return nearestLeaders.first.id;
    if (otherLeaders.isNotEmpty) return otherLeaders.first.id;
    if (superadmins.isNotEmpty) return superadmins.first.id;
    return null;
  }

  List<UserProfile> get allUnique {
    final map = <String, UserProfile>{};
    for (final p in [...nearestLeaders, ...otherLeaders, ...superadmins]) {
      map[p.id] = p;
    }
    return map.values.toList();
  }
}
