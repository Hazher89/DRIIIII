import 'user_profile.dart';

/// Hvem avsender kan velge ved innrapportering av avvik.
class TicketAssigneeOptions {
  /// Avdelingsleder(e) — nærmeste leder for ansattens avdeling.
  final List<UserProfile> nearestLeaders;

  /// Sentral eskalering (vises kun med navn, uten rolletittel).
  final List<UserProfile> superadmins;

  const TicketAssigneeOptions({
    this.nearestLeaders = const [],
    this.superadmins = const [],
  });

  bool get isEmpty => nearestLeaders.isEmpty && superadmins.isEmpty;

  /// Standardvalg: første nærmeste leder, ellers første superadmin.
  String? get defaultAssigneeId {
    if (nearestLeaders.isNotEmpty) return nearestLeaders.first.id;
    if (superadmins.isNotEmpty) return superadmins.first.id;
    return null;
  }

  List<UserProfile> get allUnique {
    final map = <String, UserProfile>{};
    for (final p in [...nearestLeaders, ...superadmins]) {
      map[p.id] = p;
    }
    return map.values.toList();
  }
}
