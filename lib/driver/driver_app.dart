import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/driftpro_client.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/system_ui_sync.dart';
import '../core/theme/theme_notifier.dart';
import 'driver_access_gate.dart';
import '../dispatch/dispatch_auth_screen.dart';

/// Sjåfør-app — lager, rute, GPS, PoD (koblet DriftPro Supabase).
class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();

    return SystemUiSync(
      child: MaterialApp(
        title: '${DriftProClient.displayName} Sjåfør',
        debugShowCheckedModeBanner: false,
        theme: DriftProTheme.lightTheme,
        darkTheme: DriftProTheme.darkTheme,
        themeMode: themeNotifier.themeMode,
        home: StreamBuilder<AuthState>(
          stream: Supabase.instance.client.auth.onAuthStateChange,
          builder: (context, snapshot) {
            final session =
                snapshot.data?.session ?? Supabase.instance.client.auth.currentSession;
            if (session != null) return const DriverAccessGate();
            return const DispatchAuthScreen();
          },
        ),
      ),
    );
  }
}
