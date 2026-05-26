import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/driftpro_client.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/theme_notifier.dart';
import 'driver/driver_app.dart';

/// Sjåfør-app entry point — lager, rute, GPS, PoD.
void main() async {
  DriftProClient.useRouteDispatchProduct();
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await initializeDateFormatting('nb');
  } catch (_) {}

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: true),
    );
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeNotifier(),
      child: const DriverApp(),
    ),
  );
}
