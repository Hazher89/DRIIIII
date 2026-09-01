import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routing/app_paths.dart';
import '../../permissions/access_session_cache.dart';
import '../chat/chat_pending_navigation.dart';
import 'push_navigation_target.dart';

/// Navigerer til riktig skjerm når brukeren trykker på et push-varsel.
abstract final class PushNavigationService {
  static GoRouter? _router;
  static PushNavigationTarget? _pending;
  static final _stream = StreamController<PushNavigationTarget>.broadcast();

  static Stream<PushNavigationTarget> get onTarget => _stream.stream;

  static void bind(GoRouter router) {
    _router = router;
    if (_pending != null) {
      unawaited(_navigate(_pending!));
    }
  }

  static PushNavigationTarget? takePending() {
    final t = _pending;
    _pending = null;
    return t;
  }

  static Future<void> handleInitialMessage() async {
    if (kIsWeb) return;
    try {
      final msg = await FirebaseMessaging.instance.getInitialMessage();
      if (msg != null) await handleRemoteMessage(msg);
    } catch (e) {
      debugPrint('push initial message: $e');
    }
  }

  static Future<void> handleRemoteMessage(RemoteMessage message) async {
    await handleMap(message.data);
  }

  static Future<void> handlePayload(String? payload) async {
    if (payload == null || payload.trim().isEmpty) return;

    final trimmed = payload.trim();
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        await handleMap(Map<String, dynamic>.from(decoded));
        return;
      }
    } catch (_) {}

    // Legacy: bare UUID (rute eller trekk)
    if (trimmed.contains('-') && trimmed.length >= 32) {
      await handleMap({'route_share_id': trimmed});
      return;
    }
    await handleMap({'case_id': trimmed});
  }

  static Future<void> handleMap(Map<String, dynamic> data) async {
    final target = PushNavigationTarget.fromMap(data);
    if (target == null) return;
    await _navigate(target);
  }

  static Future<void> flushAfterLogin() async {
    final t = _pending;
    if (t != null) await _navigate(t);
  }

  static Future<void> _navigate(PushNavigationTarget target) async {
    _pending = target;

    if (Supabase.instance.client.auth.currentSession == null) {
      return;
    }

    final router = _router;
    if (router == null) return;

    if (target.isPartnerScope) {
      final tab = target.portalTab;
      router.go(AppPaths.portalPath(tab: tab));
      _stream.add(target);
      _pending = target;
      return;
    }

    if (target.kind == PushNavKind.chatMessage && target.id != null) {
      ChatPendingNavigation.setRoom(target.id!);
      final profile = AccessSessionCache.profile;
      if (profile?.isPartnerPortalUser == true) {
        router.go(AppPaths.portalPath(tab: 'meldinger'));
      } else {
        router.go(AppPaths.chat);
      }
      _stream.add(target);
      _pending = null;
      return;
    }

    final path = target.maviPath;
    if (path != null) {
      router.go(path);
      _pending = null;
      return;
    }

    debugPrint('push navigation: ukjent mål ${target.kind}');
  }
}
