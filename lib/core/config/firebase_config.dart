import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase/FCM — `--dart-define` ved build, eller `ios/Firebase.env` → GoogleService-Info.plist.
abstract final class FirebaseConfig {
  static const apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: '',
  );
  static const appId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '',
  );
  static const messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '',
  );
  static const projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: '',
  );

  static bool get isConfigured =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty &&
      !apiKey.startsWith('YOUR_');

  static FirebaseOptions? get dartDefineOptions {
    if (!isConfigured) return null;
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
    );
  }

  /// Prefer native GoogleService-Info.plist / google-services.json when present.
  static Future<void> initializeApp() async {
    if (Firebase.apps.isNotEmpty) return;

    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      try {
        await Firebase.initializeApp();
        return;
      } catch (e) {
        debugPrint('Firebase native init failed, trying dart-define: $e');
      }
    }

    final options = dartDefineOptions;
    if (options == null) {
      throw StateError('Firebase is not configured');
    }
    await Firebase.initializeApp(options: options);
  }
}
