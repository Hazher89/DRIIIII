import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Logger ut og lar [DriftProApp] sin auth-StreamBuilder vise innlogging igjen.
Future<void> signOutFromPortal(BuildContext context) async {
  final auth = Supabase.instance.client.auth;
  try {
    await auth.signOut(scope: SignOutScope.local);
  } catch (_) {
    await auth.signOut();
  }
  if (context.mounted && auth.currentSession != null) {
    try {
      await auth.signOut(scope: SignOutScope.global);
    } catch (_) {}
  }
}
