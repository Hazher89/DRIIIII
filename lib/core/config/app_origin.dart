import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Production URL for auth redirects and e-postlenker (web).
const String kProductionOrigin = 'https://driftpro.no';

/// Deep link for native iOS/Android OAuth-retur (må være i Supabase Auth redirect URLs).
const String kNativeAuthRedirect = 'no.driftpro.driftpro://login-callback/';

/// Brukes for OAuth og magic links.
String get appAuthRedirectOrigin {
  if (!kIsWeb) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.android:
        return kNativeAuthRedirect;
      default:
        break;
    }
  }

  final origin = Uri.base.origin.trim();
  if (origin.isEmpty) return kProductionOrigin;
  if (origin.contains('localhost') || origin.contains('127.0.0.1')) {
    return origin;
  }
  return kProductionOrigin;
}
