import 'package:flutter/foundation.dart';

import '../../models/user_profile.dart';
import 'user_access.dart';

/// Sist kjente profil for synkron route-guard (oppdateres fra shell / login).
abstract final class AccessSessionCache {
  static UserProfile? _profile;
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static UserProfile? get profile => _profile;

  static UserAccess? get access =>
      _profile == null ? null : UserAccess(_profile!);

  static void setProfile(UserProfile? profile) {
    _profile = profile;
    revision.value++;
  }

  static void clear() {
    _profile = null;
    revision.value++;
  }
}
