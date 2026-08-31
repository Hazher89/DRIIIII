import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../config/driftpro_client.dart';
import '../../config/firebase_config.dart';
import '../supabase_service.dart';
import 'push_navigation_service.dart';

/// Push-varsler på mobil — FCM når konfigurert, ellers lokale varsler via Realtime.
abstract final class PushNotificationService {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static bool _localReady = false;
  static bool _firebaseReady = false;
  static bool _lastRegistrationOk = false;
  static String? _lastRegisteredToken;

  static bool get lastRegistrationOk => _lastRegistrationOk;

  /// Klargjør kanaler uten å spørre om varsel-tillatelse (Apple: kun ved behov).
  static Future<void> bootstrapAfterLogin() async {
    if (!DriftProClient.isMobile || kIsWeb) return;
    await _ensureLocalNotifications();
    await _ensureFirebaseMessaging(requestPermission: false);
    await PushNavigationService.flushAfterLogin();
  }

  /// Kall etter at brukeren har gitt varsel-tillatelse (eller allerede har den).
  static Future<bool> registerAfterPermissionGranted() async {
    if (!DriftProClient.isMobile || kIsWeb) return false;
    await _ensureLocalNotifications();
    return _ensureFirebaseMessaging(requestPermission: true);
  }

  /// Prøv på nytt etter app-resume eller når APNs-token kommer senere (iOS).
  static Future<bool> syncRegistration({bool requestPermission = false}) async {
    if (!DriftProClient.isMobile || kIsWeb) return false;
    await _ensureLocalNotifications();
    return _ensureFirebaseMessaging(requestPermission: requestPermission);
  }

  static Future<void> deactivateOnLogout() async {
    _lastRegistrationOk = false;
    _lastRegisteredToken = null;
    if (!SupabaseService.isConfigured) return;
    try {
      await SupabaseService.client.rpc('deactivate_push_devices');
    } catch (e) {
      debugPrint('deactivate_push_devices: $e');
    }
  }

  static Future<void> showPushNotification({
    required String title,
    required String body,
    String? payload,
    int? notificationId,
  }) async {
    await _ensureLocalNotifications();
    await _local.show(
      id: notificationId ??
          payload?.hashCode ??
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'driftpro_push',
          'DriftPro',
          channelDescription: 'Varsler fra DriftPro',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  static Future<void> showRouteAssigned({
    required String title,
    required String body,
    String? routeShareId,
  }) async {
    await showPushNotification(
      title: title,
      body: body,
      payload: routeShareId == null
          ? null
          : jsonEncode({
              'type': 'partner_route',
              'route_share_id': routeShareId,
            }),
    );
  }

  static Future<void> _ensureLocalNotifications() async {
    if (_localReady) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) {
        unawaited(PushNavigationService.handlePayload(response.payload));
      },
      onDidReceiveBackgroundNotificationResponse: pushNotificationTapBackground,
    );
    if (Platform.isAndroid) {
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'driftpro_push',
              'DriftPro',
              description: 'Varsler fra DriftPro',
              importance: Importance.high,
            ),
          );
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'partner_routes',
              'Ruter',
              description: 'Nye ruter tildelt sjåfør',
              importance: Importance.high,
            ),
          );
    }
    _localReady = true;
  }

  static Future<bool> _ensureFirebaseMessaging({
    required bool requestPermission,
  }) async {
    try {
      if (!_firebaseReady) {
        await FirebaseConfig.initializeApp();
        FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
        FirebaseMessaging.onMessage.listen((message) {
          final n = message.notification;
          final title = n?.title ?? message.data['title'] as String? ?? 'DriftPro';
          final body = n?.body ?? message.data['body'] as String? ?? '';
          if (body.isEmpty && n == null) return;
          unawaited(showPushNotification(
            title: title,
            body: body,
            payload: jsonEncode(message.data),
          ));
        });
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
          unawaited(PushNavigationService.handleRemoteMessage(message));
        });
        FirebaseMessaging.instance.onTokenRefresh.listen(_persistToken);
        _firebaseReady = true;
      }

      final messaging = FirebaseMessaging.instance;

      if (requestPermission) {
        await messaging.requestPermission(alert: true, badge: true, sound: true);
      }

      final settings = await messaging.getNotificationSettings();
      final allowed =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!allowed) {
        _lastRegistrationOk = false;
        return false;
      }

      if (Platform.isIOS) {
        await _waitForApnsToken(messaging);
      }

      final token = await _fetchFcmTokenWithRetry(messaging);
      if (token != null) {
        await _persistToken(token);
      }

      return _lastRegistrationOk;
    } catch (e) {
      _lastRegistrationOk = false;
      debugPrint('Firebase messaging init: $e');
      return false;
    }
  }

  static Future<void> _waitForApnsToken(FirebaseMessaging messaging) async {
    for (var i = 0; i < 8; i++) {
      final apns = await messaging.getAPNSToken();
      if (apns != null && apns.isNotEmpty) return;
      await Future<void>.delayed(Duration(milliseconds: 500 + (i * 250)));
    }
  }

  static Future<String?> _fetchFcmTokenWithRetry(
    FirebaseMessaging messaging,
  ) async {
    for (var i = 0; i < 5; i++) {
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) return token;
      await Future<void>.delayed(Duration(milliseconds: 800 + (i * 400)));
    }
    return messaging.getToken();
  }

  static Future<void> _persistToken(String token) async {
    if (!SupabaseService.isConfigured) return;
    if (_lastRegisteredToken == token && _lastRegistrationOk) return;

    try {
      await SupabaseService.client.rpc('upsert_push_device', params: {
        'p_fcm_token': token,
        'p_platform': Platform.isIOS ? 'ios' : 'android',
      });
      _lastRegisteredToken = token;
      _lastRegistrationOk = true;
      debugPrint('upsert_push_device OK (${token.substring(0, 12)}...)');
    } catch (e) {
      _lastRegistrationOk = false;
      debugPrint('upsert_push_device: $e');
    }
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await FirebaseConfig.initializeApp();
  } catch (_) {
    return;
  }
}

@pragma('vm:entry-point')
void pushNotificationTapBackground(NotificationResponse response) {
  PushNavigationService.handlePayload(response.payload);
}
