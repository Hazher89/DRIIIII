import '../../models/user_profile.dart';
import 'user_access.dart';

/// Sist kjente profil for synkron route-guard (oppdateres fra shell / login).
abstract final class AccessSessionCache {
  static UserProfile? _profile;

  static UserProfile? get profile => _profile;

  static UserAccess? get access =>
      _profile == null ? null : UserAccess(_profile!);

  static void setProfile(UserProfile? profile) {
    _profile = profile;
  }

  static void clear() => _profile = null;
}
