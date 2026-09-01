import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/driftpro_client.dart';
import '../core/layout/keyboard_dismiss_scope.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/system_ui_sync.dart';
import 'dispatch_access_gate.dart';
import 'dispatch_auth_screen.dart';

/// Mac/PC ruteplanlegger — egen app, samme Supabase som driftpro.no.
class DispatchApp extends StatelessWidget {
  const DispatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SystemUiSync(
      child: MaterialApp(
        title: DriftProClient.displayName,
        debugShowCheckedModeBanner: false,
        theme: DriftProTheme.lightTheme,
        darkTheme: DriftProTheme.lightTheme,
        themeMode: ThemeMode.light,
        builder: (context, child) => KeyboardDismissScope(
          child: child ?? const SizedBox.shrink(),
        ),
        home: StreamBuilder<AuthState>(
          stream: Supabase.instance.client.auth.onAuthStateChange,
          builder: (context, snapshot) {
            final session =
                snapshot.data?.session ?? Supabase.instance.client.auth.currentSession;
            if (session != null) {
              return const DispatchAccessGate();
            }
            return const DispatchAuthScreen();
          },
        ),
      ),
    );
  }
}
