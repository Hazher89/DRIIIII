import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_origin.dart';
import 'oauth_browser_redirect_stub.dart'
    if (dart.library.html) 'oauth_browser_redirect_web.dart';

/// Starter Google/Apple OAuth for ansatte (og nye App Store-brukere).
///
/// Logger ut eksisterende sesjon først, så provider-skjermen alltid vises.
Future<bool> startEmployeeOAuthSignIn(OAuthProvider provider) async {
  final auth = Supabase.instance.client.auth;
  if (auth.currentSession != null) {
    await auth.signOut();
  }

  final redirectTo = appAuthRedirectOrigin;

  if (kIsWeb) {
    final res = await auth.getOAuthSignInUrl(
      provider: provider,
      redirectTo: redirectTo,
    );
    assignBrowserLocation(res.url);
    return true;
  }

  return auth.signInWithOAuth(
    provider,
    redirectTo: redirectTo,
  );
}
