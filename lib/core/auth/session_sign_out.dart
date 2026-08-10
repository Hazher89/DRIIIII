import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../permissions/access_session_cache.dart';
import '../routing/app_paths.dart';
import '../services/notification/push_notification_service.dart';

/// Logger ut og lar [DriftProApp] sin auth-StreamBuilder vise innlogging igjen.
Future<void> signOutFromPortal(BuildContext context) async {
  // Lukk eventuelle sheets/dialoger først for å unngå dispose-asserts i widget-treet.
  final nav = Navigator.of(context, rootNavigator: true);
  if (nav.canPop()) {
    nav.popUntil((r) => r.isFirst);
  }
  await Future<void>.delayed(Duration.zero);

  AccessSessionCache.clear();
  final auth = Supabase.instance.client.auth;
  try {
    await auth.signOut(scope: SignOutScope.local);
  } catch (_) {
    try {
      await auth.signOut();
    } catch (_) {}
  }
  if (context.mounted && auth.currentSession != null) {
    try {
      await auth.signOut(scope: SignOutScope.global);
    } catch (_) {}
  }
  await PushNotificationService.deactivateOnLogout();
  if (context.mounted) {
    GoRouter.of(context).go(AppPaths.login);
  }
}
