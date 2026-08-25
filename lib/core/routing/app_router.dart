import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../screens/absence/absence_screen.dart';
import '../../screens/admin/access_control_screen.dart';
import '../../screens/admin/dropbox_storage_settings_screen.dart';
import '../../screens/admin/kiosk_settings_screen.dart';
import '../../screens/auth/access_denied_screen.dart';
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
import '../../screens/hms/training/sop_training_screen.dart';
import '../../screens/hms/risk_assessment/risk_assessment_list_screen.dart';
import '../../screens/hms/risk_assessment/risk_matrix_screen.dart';
import '../../screens/hms/safety_rounds/safety_round_list_screen.dart';
import '../../screens/hms/sja/sja_list_screen.dart';
import '../../screens/more/about_driftpro_screen.dart';
import '../../screens/more/vision/vision_cameras_screen.dart';
import '../../screens/more/vision/vision_events_screen.dart';
import '../../screens/uniform/uniform_monitor_screen.dart';
import '../../screens/more/help_support_screen.dart';
import '../../screens/more/assistant_settings_screen.dart';
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
import '../services/supabase_service.dart';
import '../permissions/access_keys.dart';
import '../permissions/access_session_cache.dart';
import '../permissions/permission_gate.dart';
import '../permissions/route_access_map.dart';
import 'app_paths.dart';
import 'auth_refresh_listenable.dart';

Widget _guardPath(GoRouterState state, Widget child) {
  final req = RouteAccessMap.requirementForUri(state.uri);
  if (req == null) return child;
  return PermissionGuard(
    profile: AccessSessionCache.profile,
    areaId: req.areaId,
    accessKey: req.legacyAccessKey ?? AccessKeys.more,
    action: req.action,
    requirement: req,
    guardUri: state.uri,
    child: child,
  );
}

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

/// Delt root-navigator — brukes bl.a. av web-chat (utenfor shell-treet).
final GlobalKey<NavigatorState> driftProRootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

GoRouter createAppRouter({required AuthRefreshListenable authRefresh}) {
  Duration infoskjermRefreshInterval(Uri uri) {
    final sec = int.tryParse(uri.queryParameters['refresh'] ?? '');
    if (sec != null && sec >= 30 && sec <= 900) {
      return Duration(seconds: sec);
    }
    return const Duration(minutes: 2);
  }

  return GoRouter(
    navigatorKey: driftProRootNavigatorKey,
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
      final looksLikePortal = SupabaseService.emailLooksLikePortal(email);

      if (looksLikePortal &&
          path != AppPaths.portal &&
          !path.startsWith('${AppPaths.portal}/') &&
          path != AppPaths.login &&
          path != AppPaths.accessDenied &&
          !AppPaths.isPublicPath(path)) {
        final tab = state.uri.queryParameters['tab'];
        return AppPaths.portalPath(tab: tab);
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

      // Tilgangsjekk for deep links (bruk cache — oppdateres etter login/shell).
      // Mangler tilgang → egen «Ingen tilgang»-side (ikke innhold bak lenken).
      if (!looksLikePortal &&
          path != AppPaths.login &&
          path != AppPaths.accessDenied &&
          !path.startsWith('${AppPaths.portal}/') &&
          path != AppPaths.portal) {
        final access = AccessSessionCache.access;
        if (access != null && !RouteAccessMap.allowsUri(access, state.uri)) {
          return AppPaths.accessDeniedPath(from: state.uri.toString());
        }
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppPaths.login,
        builder: (context, state) => const AuthGateScreen(),
      ),
      GoRoute(
        path: AppPaths.accessDenied,
        builder: (context, state) => AccessDeniedScreen(
          attemptedPath: state.uri.queryParameters['from'],
        ),
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
                builder: (context, state) => _guardPath(
                  state,
                  DashboardScreen(
                    onNavigateByAccess: (accessKey) {
                      final path = AppPaths.pathForAccess(accessKey);
                      if (path != null) context.go(path);
                    },
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPaths.surveys,
                builder: (context, state) => _guardPath(
                  state,
                  const SurveyListScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPaths.absence,
                builder: (context, state) => _guardPath(
                  state,
                  AbsenceScreen(
                    initialTab: state.uri.queryParameters['tab'],
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPaths.tickets,
                builder: (context, state) => _guardPath(
                  state,
                  const TicketsScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPaths.hms,
                builder: (context, state) => _guardPath(
                  state,
                  const HmsScreen()),
                routes: [
                  GoRoute(
                    path: 'avvik',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) =>
                        _guardPath(state, const TicketsScreen()),
                  ),
                  GoRoute(
                    path: 'risiko',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(state, RiskAssessmentListScreen(
                        initialTab: state.uri.queryParameters['tab'],
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'risikomatrise',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(state, const RiskMatrixScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'sja',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) =>
                        _guardPath(state, const SjaListScreen()),
                  ),
                  GoRoute(
                    path: 'vernerunde',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(state, const SafetyRoundListScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'utstyr',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(state, EquipmentHubScreen(
                        initialTab: state.uri.queryParameters['tab'],
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'kompetanse',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(state, CompetenceHubScreen(
                        initialTab: state.uri.queryParameters['tab'],
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'opplaering',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(state, const SopTrainingScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'dms',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(state, DmsScreen(
                        initialSection: _dmsSectionFromQuery(
                          state.uri.queryParameters['section'],
                        ),
                        initialFolderId: state.uri.queryParameters['folder'],
                        initialFolderName:
                            state.uri.queryParameters['folderName'],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPaths.uniform,
                builder: (context, state) => _guardPath(
                  state,
                  const UniformMonitorScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPaths.partners,
                builder: (context, state) => _guardPath(
                  state,
                  PartnersDashboardScreen(
                    initialTab: state.uri.queryParameters['tab'],
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'bedrift/:partnerId',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      PartnerDetailRoute(
                        partnerId: state.pathParameters['partnerId']!,
                        initialTab: state.uri.queryParameters['tab'],
                      ),
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
                builder: (context, state) => _guardPath(
                  state,
                  StemplingScreen(
                    initialTab: state.uri.queryParameters['tab'],
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPaths.more,
                builder: (context, state) => _guardPath(
                  state,
                  const MoreScreen()),
                routes: [
                  GoRoute(
                    path: 'profil',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      const ProfileScreen()),
                  ),
                  GoRoute(
                    path: 'avdelinger',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      const DepartmentsScreen()),
                  ),
                  GoRoute(
                    path: 'ansatte',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      const EmployeesScreen()),
                  ),
                  GoRoute(
                    path: 'organisasjonskart',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      const OrganizationChartScreen()),
                  ),
                  GoRoute(
                    path: 'partnere',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      PartnersDashboardScreen(
                        initialTab: state.uri.queryParameters['tab'],
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'personalmappe',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      const EmployeePersonalFolderScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'varsler',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      NotificationsHubScreen(
                        initialTab: state.uri.queryParameters['tab'],
                        initialSettingsTab: state.uri.queryParameters['settings'],
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'undersokelser',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      const SurveyListScreen()),
                  ),
                  GoRoute(
                    path: 'tilgangskontroll',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      const AccessControlScreen()),
                  ),
                  GoRoute(
                    path: 'brukergodkjenning',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      EmployeeHubScreen(
                        initialTab: state.uri.queryParameters['tab'],
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'infoskjerm',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      const KioskSettingsScreen()),
                  ),
                  GoRoute(
                    path: 'whistleblowing',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      const WhistleblowingScreen()),
                  ),
                  GoRoute(
                    path: 'dropbox',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      const DropboxStorageSettingsScreen()),
                  ),
                  GoRoute(
                    path: 'hjelp',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      const HelpSupportScreen()),
                  ),
                  GoRoute(
                    path: 'assistent',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      const AssistantSettingsScreen()),
                  ),
                  GoRoute(
                    path: 'personvern',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      const PrivacyScreen()),
                  ),
                  GoRoute(
                    path: 'om',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      const AboutDriftProScreen()),
                  ),
                  GoRoute(
                    path: 'vision-cameras',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      const VisionCamerasScreen()),
                  ),
                  GoRoute(
                    path: 'vision-events',
                    parentNavigatorKey: driftProRootNavigatorKey,
                    builder: (context, state) => _guardPath(
                      state,
                      const VisionEventsScreen()),
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
