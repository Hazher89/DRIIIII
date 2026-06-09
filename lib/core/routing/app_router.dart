import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../screens/absence/absence_screen.dart';
import '../../screens/admin/access_control_screen.dart';
import '../../screens/admin/dropbox_storage_settings_screen.dart';
import '../../screens/admin/kiosk_settings_screen.dart';
import '../../screens/auth/auth_gate_screen.dart';
import '../../screens/dashboard/dashboard_screen.dart';
import '../../screens/departments/departments_screen.dart';
import '../../screens/dms/dms_screen.dart';
import '../../screens/dms/widgets/dms_explorer_sidebar.dart';
import '../../screens/employees/employee_hub_screen.dart';
import '../../screens/employees/employee_personal_folder_screen.dart';
import '../../screens/employees/employees_screen.dart';
import '../../screens/hms/competence/competence_hub_screen.dart';
import '../../screens/hms/equipment/equipment_hub_screen.dart';
import '../../screens/hms/hms_screen.dart';
import '../../screens/hms/risk_assessment/risk_assessment_list_screen.dart';
import '../../screens/hms/risk_assessment/risk_matrix_screen.dart';
import '../../screens/hms/safety_rounds/safety_round_list_screen.dart';
import '../../screens/hms/sja/sja_list_screen.dart';
import '../../screens/more/about_driftpro_screen.dart';
import '../../screens/more/help_support_screen.dart';
import '../../screens/more/more_screen.dart';
import '../../screens/more/organization_chart_screen.dart';
import '../../screens/more/privacy_screen.dart';
import '../../screens/more/whistleblowing_screen.dart';
import '../../screens/online/online_presence_screen.dart';
import '../../screens/partners/partner_detail_route.dart';
import '../../screens/partners/partner_portal_route.dart';
import '../../screens/partners/partners_dashboard_screen.dart';
import '../../screens/profile/notifications_hub_screen.dart';
import '../../screens/profile/profile_screen.dart';
import '../../screens/public/public_tracking_screen.dart';
import '../../screens/shell/main_shell.dart';
import '../../screens/stempling/kiosk/kiosk_screen.dart';
import '../../screens/stempling/stempling_screen.dart';
import '../../screens/surveys/survey_list_screen.dart';
import '../../screens/surveys/survey_player_screen.dart';
import '../../screens/tickets/tickets_screen.dart';
import 'app_paths.dart';
import 'auth_refresh_listenable.dart';

DmsExplorerSection? _dmsSectionFromQuery(String? value) {
  switch (value) {
    case 'shared':
      return DmsExplorerSection.shared;
    case 'starred':
      return DmsExplorerSection.starred;
    case 'recent':
      return DmsExplorerSection.recent;
    case 'home':
      return DmsExplorerSection.home;
    default:
      return null;
  }
}

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
        final returnTo = Uri.encodeComponent(state.uri.toString());
        return '${AppPaths.login}?returnTo=$returnTo';
      }

      final user = Supabase.instance.client.auth.currentUser;
      final email = user?.email?.trim().toLowerCase() ?? '';
      final looksLikePortal = email.endsWith('.portal') ||
          email.endsWith('@portal.driftpro.no');

      if (looksLikePortal &&
          path != AppPaths.portal &&
          !path.startsWith('${AppPaths.portal}/') &&
          path != AppPaths.login &&
          !AppPaths.isPublicPath(path)) {
        final tab = state.uri.queryParameters['tab'];
        return AppPaths.portalPath(tab: tab);
      }

      if (!looksLikePortal &&
          (path == AppPaths.portal || path.startsWith('${AppPaths.portal}/'))) {
        return AppPaths.dashboard;
      }

      if (path == AppPaths.login) {
        final returnTo = state.uri.queryParameters['returnTo'];
        if (returnTo != null && returnTo.isNotEmpty) {
          return Uri.decodeComponent(returnTo);
        }
        return AppPaths.dashboard;
      }
      if (state.uri.queryParameters['dropbox'] == 'connected' &&
          path != AppPaths.moreDropbox) {
        return '${AppPaths.moreDropbox}?dropbox=connected';
      }
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
          previewMode: state.uri.queryParameters['preview'] == 'true',
        ),
      ),
      GoRoute(
        path: '/track/:token',
        builder: (context, state) => PublicTrackingScreen(
          token: state.pathParameters['token']!,
        ),
      ),
      GoRoute(
        path: AppPaths.stemple,
        builder: (context, state) => const KioskScreen(slug: 'stemple'),
      ),
      GoRoute(
        path: '${AppPaths.stemple}/:slug',
        builder: (context, state) => KioskScreen(
          slug: state.pathParameters['slug']!,
        ),
      ),
      GoRoute(
        path: '${AppPaths.kiosk}/:slug',
        builder: (context, state) => KioskScreen(
          slug: state.pathParameters['slug']!,
        ),
      ),
      GoRoute(
        path: AppPaths.live,
        builder: (context, state) => OnlinePresenceScreen(
          refreshInterval: infoskjermRefreshInterval(state.uri),
        ),
      ),
      GoRoute(
        path: AppPaths.portal,
        builder: (context, state) => PartnerPortalRoute(
          initialTab: state.uri.queryParameters['tab'],
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
                builder: (context, state) => AbsenceScreen(
                  initialTab: state.uri.queryParameters['tab'],
                ),
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
                routes: [
                  GoRoute(
                    path: 'avvik',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const TicketsScreen(),
                  ),
                  GoRoute(
                    path: 'risiko',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => RiskAssessmentListScreen(
                      initialTab: state.uri.queryParameters['tab'],
                    ),
                  ),
                  GoRoute(
                    path: 'risikomatrise',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const RiskMatrixScreen(),
                  ),
                  GoRoute(
                    path: 'sja',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const SjaListScreen(),
                  ),
                  GoRoute(
                    path: 'vernerunde',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const SafetyRoundListScreen(),
                  ),
                  GoRoute(
                    path: 'utstyr',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => EquipmentHubScreen(
                      initialTab: state.uri.queryParameters['tab'],
                    ),
                  ),
                  GoRoute(
                    path: 'kompetanse',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => CompetenceHubScreen(
                      initialTab: state.uri.queryParameters['tab'],
                    ),
                  ),
                  GoRoute(
                    path: 'dms',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => DmsScreen(
                      initialSection: _dmsSectionFromQuery(
                        state.uri.queryParameters['section'],
                      ),
                      initialFolderId: state.uri.queryParameters['folder'],
                      initialFolderName: state.uri.queryParameters['folderName'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPaths.partners,
                builder: (context, state) => PartnersDashboardScreen(
                  initialTab: state.uri.queryParameters['tab'],
                ),
                routes: [
                  GoRoute(
                    path: 'bedrift/:partnerId',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => PartnerDetailRoute(
                      partnerId: state.pathParameters['partnerId']!,
                      initialTab: state.uri.queryParameters['tab'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPaths.stempling,
                builder: (context, state) => StemplingScreen(
                  initialTab: state.uri.queryParameters['tab'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPaths.more,
                builder: (context, state) => const MoreScreen(),
                routes: [
                  GoRoute(
                    path: 'profil',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const ProfileScreen(),
                  ),
                  GoRoute(
                    path: 'avdelinger',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const DepartmentsScreen(),
                  ),
                  GoRoute(
                    path: 'ansatte',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const EmployeesScreen(),
                  ),
                  GoRoute(
                    path: 'organisasjonskart',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const OrganizationChartScreen(),
                  ),
                  GoRoute(
                    path: 'partnere',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => PartnersDashboardScreen(
                      initialTab: state.uri.queryParameters['tab'],
                    ),
                  ),
                  GoRoute(
                    path: 'personalmappe',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const EmployeePersonalFolderScreen(),
                  ),
                  GoRoute(
                    path: 'varsler',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => NotificationsHubScreen(
                      initialTab: state.uri.queryParameters['tab'],
                      initialSettingsTab: state.uri.queryParameters['settings'],
                    ),
                  ),
                  GoRoute(
                    path: 'undersokelser',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const SurveyListScreen(),
                  ),
                  GoRoute(
                    path: 'tilgangskontroll',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const AccessControlScreen(),
                  ),
                  GoRoute(
                    path: 'brukergodkjenning',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => EmployeeHubScreen(
                      initialTab: state.uri.queryParameters['tab'],
                    ),
                  ),
                  GoRoute(
                    path: 'infoskjerm',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const KioskSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'whistleblowing',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const WhistleblowingScreen(),
                  ),
                  GoRoute(
                    path: 'dropbox',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const DropboxStorageSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'hjelp',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const HelpSupportScreen(),
                  ),
                  GoRoute(
                    path: 'personvern',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const PrivacyScreen(),
                  ),
                  GoRoute(
                    path: 'om',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const AboutDriftProScreen(),
                  ),
                ],
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
