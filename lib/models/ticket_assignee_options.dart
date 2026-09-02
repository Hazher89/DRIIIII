import 'user_profile.dart';

/// Hvem avsender kan velge ved avvik / HMS — kun egen leder + ledelsen.
class TicketAssigneeOptions {
  /// Avdelingsleder(e) for ansattens egen avdeling.
  final List<UserProfile> nearestLeaders;

  /// Ikke i bruk for ansatte (holdes tom — andre avdelingers ledere skjuless).
  final List<UserProfile> otherLeaders;

  /// Ledelsen: Tommy, Nico, Hazher (feltnavn beholdes for bakoverkompatibilitet).
  final List<UserProfile> superadmins;

  const TicketAssigneeOptions({
    this.nearestLeaders = const [],
    this.otherLeaders = const [],
    this.superadmins = const [],
  });

  /// Alias: Tommy / Nico / Hazher.
  List<UserProfile> get leadership => superadmins;

  bool get isEmpty =>
      nearestLeaders.isEmpty && otherLeaders.isEmpty && superadmins.isEmpty;

  /// Standardvalg: egen leder, ellers første i ledelsen.
  String? get defaultAssigneeId {
    if (nearestLeaders.isNotEmpty) return nearestLeaders.first.id;
    if (superadmins.isNotEmpty) return superadmins.first.id;
    if (otherLeaders.isNotEmpty) return otherLeaders.first.id;
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
