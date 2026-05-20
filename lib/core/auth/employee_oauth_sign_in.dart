import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_origin.dart';
import 'oauth_browser_redirect_stub.dart'
    if (dart.library.html) 'oauth_browser_redirect_web.dart';

/// Starts Google/Apple OAuth for MAVI employees.
///
/// Signs out any existing session first so the user always sees the provider
/// login screen instead of silently reusing a cached session.
Future<bool> startEmployeeOAuthSignIn(OAuthProvider provider) async {
  final auth = Supabase.instance.client.auth;
  if (auth.currentSession != null) {
    await auth.signOut();
  }

  if (kIsWeb) {
    final res = await auth.getOAuthSignInUrl(
      provider: provider,
      redirectTo: appAuthRedirectOrigin,
    );
    assignBrowserLocation(res.url);
    return true;
  }

  return auth.signInWithOAuth(
    provider,
    redirectTo: appAuthRedirectOrigin,
  );
}
