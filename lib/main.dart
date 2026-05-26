import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/routing/app_router.dart';
import 'core/routing/auth_refresh_listenable.dart';
import 'core/theme/app_theme.dart';
import 'core/config/driftpro_client.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/theme_notifier.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    usePathUrlStrategy();
  }

  // Kun lås portrett på mobil — desktop og web skal bruke full skjerm.
  if (DriftProClient.isMobile) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  if (!DriftProClient.isDesktop) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
      ),
    );
  }

  await _initSupabase();
  await _initDateLocales();

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeNotifier(),
      child: const DriftProApp(),
    ),
  );
}

Future<void> _initDateLocales() async {
  try {
    await initializeDateFormatting('nb');
    await initializeDateFormatting('nb_NO');
  } catch (_) {
    // Appen bruker NbDateFormat-fallback hvis locale-data mangler.
  }
}

Future<void> _initSupabase() async {
  if (!SupabaseConfig.isConfigured) {
    // Lar appen kjøre uten backend i dev/demo-modus.
    return;
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: true,
    ),
  );
}

class DriftProApp extends StatefulWidget {
  const DriftProApp({super.key});

  @override
  State<DriftProApp> createState() => _DriftProAppState();
}

class _DriftProAppState extends State<DriftProApp> {
  late final AuthRefreshListenable _authRefresh = AuthRefreshListenable();
  late final GoRouter _router = createAppRouter(authRefresh: _authRefresh);

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();

    return MaterialApp.router(
      title: DriftProClient.displayName,
      debugShowCheckedModeBanner: false,
      theme: DriftProTheme.lightTheme,
      darkTheme: DriftProTheme.darkTheme,
      themeMode: themeNotifier.themeMode,
      routerConfig: _router,
    );
  }
}
