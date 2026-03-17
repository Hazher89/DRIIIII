import 'package:flutter/foundation.dart';
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
        builder: (context, snapshot) {
          final session = snapshot.data?.session ?? Supabase.instance.client.auth.currentSession;

          if (session != null) {
            return FutureBuilder<UserProfile?>(
              // Force refresh the profile when auth state changes
              key: ValueKey('profile_${session.user.id}_${snapshot.data?.event}'),
              future: SupabaseService.fetchCurrentUserProfile(),
              builder: (context, profileSnapshot) {
                if (profileSnapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(body: Center(child: CircularProgressIndicator()));
                }
                
                final profile = profileSnapshot.data;
                
                // 1. Hvis profil mangler helt (trigger feilet eller treg)
                if (profile == null) {
                  return Scaffold(
                    body: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 24),
                            const Text('Klargjør din profil...', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            const Text('Dette tar vanligvis under 3 sekunder.', textAlign: TextAlign.center),
                            const SizedBox(height: 24),
                            if (kDebugMode) Text('User ID: ${session.user.id}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            const SizedBox(height: 48),
                            TextButton.icon(
                              onPressed: () => Supabase.instance.client.auth.signOut(),
                              icon: const Icon(Icons.logout),
                              label: const Text('Logg ut og prøv på nytt'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                // SECURITY OVERLAY (Visible in debug mode to see EXACTLY what's happening)
                Widget mainWidget;
                
                // 2. Hvis profil finnes, men onboarding mangler
                if (!profile.isOnboarded) {
                  mainWidget = OnboardingScreen(profile: profile);
                }
                // 3. Hvis profil finnes og onboarding er ferdig, men mangler godkjenning
                else if (!profile.isApproved && profile.role != UserRole.superadmin) {
                  if (kDebugMode) {
                    print('Profile ${profile.id} (Email: ${profile.email}) is not approved and not a superadmin.');
                  }
                  mainWidget = const PendingApprovalScreen();
                }
                // 4. Alt ok!
                else {
                  mainWidget = const MainShell();
                }

                if (kDebugMode) {
                  return Stack(
                    children: [
                      mainWidget,
                      Positioned(
                        top: 40,
                        right: 10,
                        child: Material(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('User: ${profile.email}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                                Text('Role: ${profile.role.name}', style: const TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                                Text('Onboarded: ${profile.isOnboarded}', style: TextStyle(color: profile.isOnboarded ? Colors.green : Colors.red, fontSize: 10)),
                                Text('Approved: ${profile.isApproved}', style: TextStyle(color: profile.isApproved ? Colors.green : Colors.red, fontSize: 10)),
                                Text('Current View: ${mainWidget.runtimeType}', style: const TextStyle(color: Colors.yellow, fontSize: 10)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return mainWidget;
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
