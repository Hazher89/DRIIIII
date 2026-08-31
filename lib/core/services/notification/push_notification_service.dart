import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../config/driftpro_client.dart';
import '../../config/firebase_config.dart';
import '../supabase_service.dart';

/// Push-varsler på mobil — FCM når konfigurert, ellers lokale varsler via Realtime.
abstract final class PushNotificationService {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static bool _localReady = false;
  static bool _firebaseReady = false;

  /// Klargjør kanaler uten å spørre om varsel-tillatelse (Apple: kun ved behov).
  static Future<void> bootstrapAfterLogin() async {
    if (!DriftProClient.isMobile || kIsWeb) return;
    await _ensureLocalNotifications();
    await _ensureFirebaseMessaging(requestPermission: false);
  }

  /// Kall etter at brukeren har gitt varsel-tillatelse (eller allerede har den).
  static Future<void> registerAfterPermissionGranted() async {
    if (!DriftProClient.isMobile || kIsWeb) return;
    await _ensureLocalNotifications();
    await _ensureFirebaseMessaging(requestPermission: true);
  }

  static Future<void> deactivateOnLogout() async {
    if (!SupabaseService.isConfigured) return;
    try {
      await SupabaseService.client.rpc('deactivate_push_devices');
    } catch (e) {
      debugPrint('deactivate_push_devices: $e');
    }
  }

  static Future<void> showRouteAssigned({
    required String title,
    required String body,
    String? routeShareId,
  }) async {
    await _ensureLocalNotifications();
    await _local.show(
      id: routeShareId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'partner_routes',
          'Ruter',
          channelDescription: 'Nye ruter tildelt sjåfør',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: routeShareId,
    );
  }

  static Future<void> _ensureLocalNotifications() async {
    if (_localReady) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    // Ikke be om iOS-tillatelse her — det skjer via NativePermissionsService.
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );
    if (Platform.isAndroid) {
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

  static Future<void> _ensureFirebaseMessaging({
    required bool requestPermission,
  }) async {
    try {
      if (!_firebaseReady) {
        await FirebaseConfig.initializeApp();
        FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
        FirebaseMessaging.onMessage.listen((message) {
          final n = message.notification;
          if (n == null) return;
          unawaited(showRouteAssigned(
            title: n.title ?? 'DriftPro',
            body: n.body ?? '',
            routeShareId: message.data['route_share_id'] as String?,
          ));
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
      if (!allowed) return;

      final token = await messaging.getToken();
      if (token != null) {
        await _persistToken(token);
      }
    } catch (e) {
      debugPrint('Firebase messaging init: $e');
    }
  }

  static Future<void> _persistToken(String token) async {
    if (!SupabaseService.isConfigured) return;
    try {
      await SupabaseService.client.rpc('upsert_push_device', params: {
        'p_fcm_token': token,
        'p_platform': Platform.isIOS ? 'ios' : 'android',
      });
    } catch (e) {
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
