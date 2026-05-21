import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/theme_notifier.dart';
import 'screens/shell/main_shell.dart';
import 'screens/auth/auth_gate_screen.dart';
import 'screens/surveys/survey_player_screen.dart';
import 'screens/online/online_presence_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
    ),
  );

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
  if (SupabaseConfig.url.startsWith('YOUR_') ||
      SupabaseConfig.anonKey.startsWith('YOUR_')) {
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

class DriftProApp extends StatelessWidget {
  const DriftProApp({super.key});

  String? _extractPublicSurveyId() {
    final querySurvey = Uri.base.queryParameters['survey'];
    if (querySurvey != null && querySurvey.trim().isNotEmpty) {
      return querySurvey.trim();
    }
    final queryShort = Uri.base.queryParameters['s'];
    if (queryShort != null && queryShort.trim().isNotEmpty) {
      return queryShort.trim();
    }

    final path = Uri.base.path;
    if (path.startsWith('/s/')) {
      return path.replaceFirst('/s/', '').trim();
    }

    final fragment = Uri.base.fragment;
    if (fragment.startsWith('/s/')) {
      return fragment.replaceFirst('/s/', '').trim();
    }
    if (fragment.startsWith('s/')) {
      return fragment.replaceFirst('s/', '').trim();
    }
    return null;
  }

  bool _isInfoskjermRoute() {
    final path = Uri.base.path.toLowerCase();
    const pathHits = ['/online', '/infoskjerm', '/wallboard'];
    for (final p in pathHits) {
      if (path == p || path.endsWith(p)) return true;
    }
    final fragment = Uri.base.fragment.toLowerCase();
    for (final p in pathHits) {
      if (fragment == p ||
          fragment.endsWith(p) ||
          fragment.contains('view=infoskjerm') ||
          fragment.contains('view=online')) {
        return true;
      }
    }
    final view = Uri.base.queryParameters['view']?.toLowerCase();
    return view == 'online' || view == 'infoskjerm' || view == 'wallboard';
  }

  Duration _infoskjermRefreshInterval() {
    final sec = int.tryParse(Uri.base.queryParameters['refresh'] ?? '');
    if (sec != null && sec >= 30 && sec <= 900) {
      return Duration(seconds: sec);
    }
    return const Duration(minutes: 2);
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();
    final publicSurveyId = _extractPublicSurveyId();
    final infoskjermRoute = _isInfoskjermRoute();

    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: DriftProTheme.lightTheme,
      darkTheme: DriftProTheme.darkTheme,
      themeMode: themeNotifier.themeMode,
      onGenerateRoute: (settings) {
        if (settings.name != null && settings.name!.startsWith('/s/')) {
          final id = settings.name!.replaceFirst('/s/', '');
          return MaterialPageRoute(
            builder: (_) => SurveyPlayerScreen(surveyId: id),
          );
        }
        return null;
      },
      home: publicSurveyId != null && publicSurveyId.isNotEmpty
          ? SurveyPlayerScreen(surveyId: publicSurveyId)
          : StreamBuilder<AuthState>(
              key: const ValueKey('auth_stream'),
              stream: Supabase.instance.client.auth.onAuthStateChange,
              builder: (context, snapshot) {
                final session =
                    snapshot.data?.session ?? Supabase.instance.client.auth.currentSession;

                if (infoskjermRoute) {
                  if (session != null) {
                    return OnlinePresenceScreen(
                      refreshInterval: _infoskjermRefreshInterval(),
                    );
                  }
                  return const AuthGateScreen();
                }
                if (session != null) {
                  return const MainShell();
                }
                return const AuthGateScreen();
              },
            ),
    );
  }
}
