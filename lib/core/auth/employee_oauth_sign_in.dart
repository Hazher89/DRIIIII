import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_origin.dart';
import 'oauth_browser_redirect_stub.dart'
    if (dart.library.html) 'oauth_browser_redirect_web.dart';

/// Starter Google/Apple OAuth for ansatte (og nye App Store-brukere).
///
/// På iOS/macOS brukes nativ Sign in with Apple (App Store-krav).
/// Logger ut eksisterende sesjon først, så provider-skjermen alltid vises.
Future<bool> startEmployeeOAuthSignIn(OAuthProvider provider) async {
  final auth = Supabase.instance.client.auth;
  if (auth.currentSession != null) {
    await auth.signOut();
  }

  if (provider == OAuthProvider.apple && _useNativeAppleSignIn) {
    await _signInWithNativeApple(auth);
    return true;
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

bool get _useNativeAppleSignIn {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

Future<void> _signInWithNativeApple(GoTrueClient auth) async {
  final rawNonce = _generateNonce();
  final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

  final credential = await SignInWithApple.getAppleIDCredential(
    scopes: [
      AppleIDAuthorizationScopes.email,
      AppleIDAuthorizationScopes.fullName,
    ],
    nonce: hashedNonce,
  );

  final idToken = credential.identityToken;
  if (idToken == null || idToken.isEmpty) {
    throw const AuthException('Apple returnerte ingen ID-token. Prøv igjen.');
  }

  await auth.signInWithIdToken(
    provider: OAuthProvider.apple,
    idToken: idToken,
    nonce: rawNonce,
  );

  // Apple gir navn kun ved første godkjenning — lagre hvis vi får det.
  final given = credential.givenName?.trim() ?? '';
  final family = credential.familyName?.trim() ?? '';
  final fullName = ('$given $family').trim();
  if (fullName.isNotEmpty) {
    try {
      await auth.updateUser(
        UserAttributes(
          data: {
            'full_name': fullName,
            if (given.isNotEmpty) 'given_name': given,
            if (family.isNotEmpty) 'family_name': family,
          },
        ),
      );
    } catch (_) {
      // Profiloppdatering er best-effort.
    }
  }
}

String _generateNonce([int length = 32]) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List.generate(
    length,
    (_) => charset[random.nextInt(charset.length)],
  ).join();
}
