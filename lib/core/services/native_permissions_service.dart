import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/driftpro_client.dart';
import '../config/firebase_config.dart';
import 'notification/push_notification_service.dart';

/// Tillatelser DriftPro ber om — kun via systemets dialog (Info.plist / Android manifest).
enum AppPermissionKind {
  notifications,
  camera,
  photos,
  location,
  microphone,
}

extension AppPermissionKindX on AppPermissionKind {
  String get title => switch (this) {
        AppPermissionKind.notifications => 'Varsler',
        AppPermissionKind.camera => 'Kamera',
        AppPermissionKind.photos => 'Bilder',
        AppPermissionKind.location => 'Posisjon',
        AppPermissionKind.microphone => 'Mikrofon',
      };

  String get deniedMessage => switch (this) {
        AppPermissionKind.notifications =>
          'Varsler er slått av. Du kan aktivere dem under Innstillinger → DriftPro.',
        AppPermissionKind.camera =>
          'Kameratilgang mangler. Åpne Innstillinger for å tillate kamera.',
        AppPermissionKind.photos =>
          'Bildetilgang mangler. Åpne Innstillinger for å tillate bilder.',
        AppPermissionKind.location =>
          'Posisjonstilgang mangler. Åpne Innstillinger for å tillate posisjon.',
        AppPermissionKind.microphone =>
          'Mikrofontilgang mangler. Åpne Innstillinger for å tillate mikrofon.',
      };

  Permission get permission => switch (this) {
        AppPermissionKind.notifications => Permission.notification,
        AppPermissionKind.camera => Permission.camera,
        AppPermissionKind.photos => Permission.photos,
        AppPermissionKind.location => Permission.locationWhenInUse,
        AppPermissionKind.microphone => Permission.microphone,
      };
}

/// Enhetens varsel-tillatelse for DriftPro (iOS/Android systeminnstillinger).
enum NotificationAuthState {
  enabled,
  disabled,
  notConfigured,
}

extension NotificationAuthStateX on NotificationAuthState {
  String get label => switch (this) {
        NotificationAuthState.enabled => 'På',
        NotificationAuthState.disabled => 'Av',
        NotificationAuthState.notConfigured => 'Ikke satt opp',
      };

  String get subtitle => switch (this) {
        NotificationAuthState.enabled =>
          'Denne enheten kan motta push-varsler fra DriftPro.',
        NotificationAuthState.disabled =>
          'Varsler er slått av for DriftPro på denne enheten.',
        NotificationAuthState.notConfigured =>
          'Varsler er ikke aktivert ennå på denne enheten.',
      };
}

abstract final class NativePermissionsService {
  static const _notificationPromptFlagFile = 'notification_permission_prompted_v1';

  static bool get _native => DriftProClient.isMobile;

  /// Apple-mønster: be kun om varsel-tillatelse etter innlogging (systemdialog).
  /// Kamera, bilder, posisjon og mikrofon spørres ved behov via [ensureCamera] m.m.
  static Future<void> promptNotificationsIfNeeded([BuildContext? context]) async {
    if (!_native) return;

    final state = await readNotificationState();
    if (state == NotificationAuthState.enabled) {
      await PushNotificationService.registerAfterPermissionGranted();
      return;
    }

    // Allerede avslått — ikke mase (Apple-mønster).
    if (state == NotificationAuthState.disabled) return;

    if (context != null && !context.mounted) return;
    await ensureNotifications(context: context);

    if (Platform.isAndroid) {
      await _markNotificationPromptAttempted();
    }
  }

  static Future<bool> _notificationPromptAttempted() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$_notificationPromptFlagFile').existsSync();
    } catch (_) {
      return false;
    }
  }

  static Future<void> _markNotificationPromptAttempted() async {
    try {
      final dir = await getApplicationSupportDirectory();
      await File('${dir.path}/$_notificationPromptFlagFile').writeAsString('1');
    } catch (_) {}
  }

  static Future<bool> ensureNotifications({BuildContext? context}) =>
      ensure(AppPermissionKind.notifications, context: context);

  static Future<bool> ensureCamera({BuildContext? context}) =>
      ensure(AppPermissionKind.camera, context: context);

  static Future<bool> ensurePhotos({BuildContext? context}) =>
      ensure(AppPermissionKind.photos, context: context);

  static Future<bool> ensureLocation({BuildContext? context}) =>
      ensure(AppPermissionKind.location, context: context);

  static Future<bool> ensureMicrophone({BuildContext? context}) =>
      ensure(AppPermissionKind.microphone, context: context);

  /// Ber om tillatelse via systemets dialog når status ikke allerede er gitt.
  /// [context] brukes kun til snackbar hvis tilgangen allerede er permanent avslått.
  static Future<bool> ensure(
    AppPermissionKind kind, {
    BuildContext? context,
  }) async {
    if (!_native) return true;

    if (kind == AppPermissionKind.notifications && Platform.isIOS) {
      final ok = await PushNotificationService.registerAfterPermissionGranted();
      if (!ok && context != null && context.mounted) {
        _snack(
          context,
          'Push-varsler er ikke aktivert. Slå på varsler for DriftPro i Innstillinger.',
          actionLabel: 'Innstillinger',
          onAction: openAppSettings,
        );
      }
      return ok;
    }

    if (kind == AppPermissionKind.notifications && Platform.isAndroid) {
      final ok = await PushNotificationService.requestSystemNotificationPermission();
      if (ok) {
        await PushNotificationService.registerAfterPermissionGranted();
      } else if (context != null && context.mounted) {
        _snack(
          context,
          kind.deniedMessage,
          actionLabel: 'Innstillinger',
          onAction: openAppSettings,
        );
      }
      return ok;
    }

    if (kind == AppPermissionKind.location) {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        if (context != null && context.mounted) {
          _snack(
            context,
            'Skru på posisjonstjenester på enheten for å bruke GPS i DriftPro.',
          );
        }
        return false;
      }
    }

    final permission = kind.permission;
    var status = await permission.status;
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return true;
    }

    if (status.isPermanentlyDenied) {
      if (context != null && context.mounted) {
        _snack(
          context,
          kind.deniedMessage,
          actionLabel: 'Innstillinger',
          onAction: openAppSettings,
        );
      }
      return false;
    }

    status = await permission.request();
    return status.isGranted || status.isLimited || status.isProvisional;
  }

  /// Les varsel-tillatelse uten å vise systemdialog (for profil / innstillinger).
  static Future<NotificationAuthState> readNotificationState() async {
    if (!_native) return NotificationAuthState.enabled;

    if (Platform.isIOS) {
      try {
        await FirebaseConfig.initializeApp();
        final settings =
            await FirebaseMessaging.instance.getNotificationSettings();
        return switch (settings.authorizationStatus) {
          AuthorizationStatus.authorized ||
          AuthorizationStatus.provisional =>
            NotificationAuthState.enabled,
          AuthorizationStatus.denied => NotificationAuthState.disabled,
          AuthorizationStatus.notDetermined =>
            NotificationAuthState.notConfigured,
        };
      } catch (_) {
        return NotificationAuthState.notConfigured;
      }
    }

    final status = await Permission.notification.status;
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return NotificationAuthState.enabled;
    }
    if (status.isPermanentlyDenied) {
      return NotificationAuthState.disabled;
    }
    if (await _notificationPromptAttempted()) {
      return NotificationAuthState.disabled;
    }
    return NotificationAuthState.notConfigured;
  }

  /// Åpner DriftPro under enhetens innstillinger (Apple-anbefalt for av/på).
  static Future<void> openNotificationSettings() => openAppSettings();

  /// Etter innlogging: klargjør varsel-kanal uten å spørre om tillatelser.
  static Future<void> bootstrapAfterLogin([BuildContext? context]) async {
    if (!_native) return;
    await PushNotificationService.bootstrapAfterLogin();
  }

  /// Snackbar + lenke til Innstillinger ved avslag (ikke tillatelses-popup).
  static Future<bool> ensureOrPrompt(
    BuildContext context, {
    required Future<bool> Function() ensure,
    required String deniedMessage,
  }) async {
    final ok = await ensure();
    if (ok || !context.mounted) return ok;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(deniedMessage),
        action: SnackBarAction(
          label: 'Innstillinger',
          onPressed: openAppSettings,
        ),
        duration: const Duration(seconds: 6),
      ),
    );
    return false;
  }

  static void _snack(
    BuildContext? context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (context == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
