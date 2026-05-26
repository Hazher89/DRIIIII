import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/driftpro_client.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/theme_notifier.dart';
import 'dispatch/dispatch_app.dart';

/// Entry point for Mac/PC ruteplanlegger — KUN planlegging, data fra DriftPro Supabase.
void main() async {
  DriftProClient.useRouteDispatchProduct();
  WidgetsFlutterBinding.ensureInitialized();

  await _initDateLocales();
  await _initSupabase();

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeNotifier(),
      child: const DispatchApp(),
    ),
  );
}

Future<void> _initDateLocales() async {
  try {
    await initializeDateFormatting('nb');
    await initializeDateFormatting('nb_NO');
  } catch (_) {}
}

Future<void> _initSupabase() async {
  if (!SupabaseConfig.isConfigured) return;

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: true,
    ),
  );
}
