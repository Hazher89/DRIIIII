import 'package:flutter/foundation.dart';

import '../../models/user_profile.dart';
import 'user_access.dart';

/// Sist kjente profil for synkron route-guard (oppdateres fra shell / login).
abstract final class AccessSessionCache {
  static UserProfile? _profile;
  static bool _partnerPortalSession = false;
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static UserProfile? get profile => _profile;

  static UserAccess? get access =>
      _profile == null ? null : UserAccess(_profile!);

  /// Partnerinnlogging — også når Auth-e-post er vanlig Gmail (ikke @portal.driftpro.no).
  static bool get isPartnerPortalSession =>
      _partnerPortalSession || (_profile?.isPartnerPortalUser == true);

  static void setProfile(UserProfile? profile) {
    _profile = profile;
    if (profile?.isPartnerPortalUser == true) {
      _partnerPortalSession = true;
    }
    revision.value++;
  }

  static void setPartnerPortalSession(bool value) {
    _partnerPortalSession = value;
    revision.value++;
  }

  static void clear() {
    _profile = null;
    _partnerPortalSession = false;
    revision.value++;
  }
}
