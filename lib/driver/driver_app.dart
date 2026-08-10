import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/driftpro_client.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/system_ui_sync.dart';
import 'driver_access_gate.dart';
import '../dispatch/dispatch_auth_screen.dart';

/// Sjåfør-app — lager, rute, GPS, PoD (koblet DriftPro Supabase).
class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SystemUiSync(
      child: MaterialApp(
        title: '${DriftProClient.displayName} Sjåfør',
        debugShowCheckedModeBanner: false,
        theme: DriftProTheme.lightTheme,
        darkTheme: DriftProTheme.lightTheme,
        themeMode: ThemeMode.light,
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
