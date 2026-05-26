import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../screens/absence/absence_screen.dart';
import '../../screens/auth/auth_gate_screen.dart';
import '../../screens/dashboard/dashboard_screen.dart';
import '../../screens/hms/hms_screen.dart';
import '../../screens/more/more_screen.dart';
import '../../screens/online/online_presence_screen.dart';
import '../../screens/partners/partners_dashboard_screen.dart';
import '../../screens/public/public_tracking_screen.dart';
import '../../screens/shell/main_shell.dart';
import '../../screens/surveys/survey_list_screen.dart';
import '../../screens/surveys/survey_player_screen.dart';
import '../../screens/tickets/tickets_screen.dart';
import 'app_paths.dart';
import 'auth_refresh_listenable.dart';

GoRouter createAppRouter({required AuthRefreshListenable authRefresh}) {
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

  Duration infoskjermRefreshInterval(Uri uri) {
    final sec = int.tryParse(uri.queryParameters['refresh'] ?? '');
    if (sec != null && sec >= 30 && sec <= 900) {
      return Duration(seconds: sec);
    }
    return const Duration(minutes: 2);
  }

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    refreshListenable: authRefresh,
    initialLocation: AppPaths.initialLocationFromUri(Uri.base),
    redirect: (context, state) {
      final path = state.uri.path.isEmpty ? AppPaths.dashboard : state.uri.path;

      if (AppPaths.isPublicPath(path)) return null;

      if (path == AppPaths.live ||
          path == '/online' ||
          path == '/infoskjerm' ||
          path == '/wallboard') {
        if (Supabase.instance.client.auth.currentSession == null) {
          return AppPaths.login;
        }
        return null;
      }

      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        if (path == AppPaths.login) return null;
        return AppPaths.login;
      }
      if (path == AppPaths.login) return AppPaths.dashboard;
      return null;
    },
    routes: [
      GoRoute(
        path: AppPaths.login,
        builder: (context, state) => const AuthGateScreen(),
      ),
      GoRoute(
        path: '/s/:surveyId',
        builder: (context, state) => SurveyPlayerScreen(
          surveyId: state.pathParameters['surveyId']!,
        ),
      ),
      GoRoute(
        path: '/track/:token',
        builder: (context, state) => PublicTrackingScreen(
          token: state.pathParameters['token']!,
        ),
      ),
      GoRoute(
        path: AppPaths.live,
        builder: (context, state) => OnlinePresenceScreen(
          refreshInterval: infoskjermRefreshInterval(state.uri),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPaths.dashboard,
                builder: (context, state) => DashboardScreen(
                  onNavigateByAccess: (accessKey) {
                    final path = AppPaths.pathForAccess(accessKey);
                    if (path != null) context.go(path);
                  },
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPaths.surveys,
                builder: (context, state) => const SurveyListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPaths.absence,
                builder: (context, state) => const AbsenceScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPaths.tickets,
                builder: (context, state) => const TicketsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPaths.hms,
                builder: (context, state) => const HmsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPaths.partners,
                builder: (context, state) => const PartnersDashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPaths.more,
                builder: (context, state) => const MoreScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Fant ikke siden'),
            const SizedBox(height: 8),
            Text(state.uri.toString(), style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go(AppPaths.dashboard),
              child: const Text('Til dashboard'),
            ),
          ],
        ),
      ),
    ),
  );
}
