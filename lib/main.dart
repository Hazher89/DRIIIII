import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/theme_notifier.dart';
import 'screens/shell/main_shell.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/auth/pending_approval_screen.dart';
import 'screens/surveys/survey_player_screen.dart';
import 'core/services/supabase_service.dart';
import 'models/user_profile.dart';

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

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeNotifier(),
      child: const DriftProApp(),
    ),
  );
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
  );
}



class DriftProApp extends StatelessWidget {
  const DriftProApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();

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
      home: StreamBuilder<AuthState>(
        key: const ValueKey('auth_stream'),
        stream: Supabase.instance.client.auth.onAuthStateChange,
        initialData: AuthState(
          AuthChangeEvent.initialSession,
          Supabase.instance.client.auth.currentSession,
        ),
        builder: (context, snapshot) {
          final session = snapshot.data?.session;

          if (session != null) {
            return FutureBuilder<UserProfile?>(
              future: SupabaseService.fetchCurrentUserProfile(),
              builder: (context, profileSnapshot) {
                if (profileSnapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(body: Center(child: CircularProgressIndicator()));
                }
                
                final profile = profileSnapshot.data;
                if (profile != null && !profile.isOnboarded) {
                  return OnboardingScreen(profile: profile);
                }
                
                // SuperAdmin trenger ikke godkjenning (viktig for å ikke låse seg ute)
                if (profile != null && !profile.isApproved && profile.role != UserRole.superadmin) {
                  return const PendingApprovalScreen();
                }
                
                return const MainShell();
              },
            );
          } else {
            return const LoginScreen();
          }
        },
      ),
    );
  }
}
