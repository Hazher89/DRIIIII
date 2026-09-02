import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/routing/app_paths.dart';
import '../../core/routing/route_url_sync.dart';
import '../../core/auth/session_sign_out.dart';
import '../../core/services/chat/chat_flag_service.dart';
import '../../core/services/chat/chat_pending_navigation.dart';
import '../../core/services/chat/chat_unread_service.dart';
import '../../core/services/chat/chat_realtime_notification_service.dart';
import '../../core/services/hms/hms_pdf_export_service.dart';
import '../../core/services/partner/mavi_unit_codes.dart';
import '../../core/services/partner/partner_portal_scope.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/partner/vehicle_inspection_pdf.dart';
import '../../core/services/notification/partner_route_push_listener.dart';
import '../../core/services/notification/push_navigation_service.dart';
import '../../core/services/notification/push_navigation_target.dart';
import '../../core/services/notification/push_notification_service.dart';
import '../../core/services/native_permissions_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/driftpro_brand_bar.dart';
import '../../models/partner/fleet_shift.dart';
import '../../models/partner/partner.dart';
import '../../models/partner/partner_links.dart';
import '../../models/partner/vehicle_inspection.dart';
import '../../models/user_profile.dart';
import '../chat/partner_chat_hub_screen.dart';
import '../../widgets/chat/chat_feature_gate.dart';
import 'driver_portal/driver_portal_docs_page.dart';
import 'driver_portal/driver_portal_fri_page.dart';
import 'driver_portal/driver_portal_overview_page.dart';
import 'driver_portal/driver_portal_routes_page.dart';
import 'owner_portal/owner_portal_deductions_page.dart';
import 'owner_portal/owner_portal_docs_page.dart';
import 'owner_portal/owner_portal_overview_page.dart';
import 'owner_portal/owner_portal_routes_page.dart';
import 'owner_portal/owner_portal_routes_focus.dart';
import 'owner_portal/owner_portal_more_page.dart';
import 'owner_portal/owner_portal_timesheet_page.dart';
import 'partner_push_navigation.dart';
import 'staff_portal/staff_portal_punch_page.dart';
import 'widgets/partner_portal_bottom_nav.dart';
import 'widgets/partner_portal_profile_page.dart';
import 'widgets/partner_route_pdf_actions.dart';
import 'widgets/partner_ui.dart' show PartnerStatusBadge;
import '../../widgets/driftpro_loading_indicator.dart';
import '../../core/layout/web_layout.dart';
import '../../core/services/nav_badge_service.dart';
import '../../core/services/partner/partner_workforce_service.dart';

DateTime _routeCalendarDay(PartnerRouteShare r) {
  final t = r.routeStartAt ?? r.shareDate;
  return DateTime(t.year, t.month, t.day);
}

bool _isActivePortalRoute(PartnerRouteShare r) {
  if (r.requiresAck) return true;
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  return !_routeCalendarDay(r).isBefore(startOfToday.subtract(const Duration(days: 1)));
}

int _compareRoutesByStartDesc(PartnerRouteShare a, PartnerRouteShare b) {
  return _routeCalendarDay(b).compareTo(_routeCalendarDay(a));
}

List<Widget> _partnerLogoutActions(BuildContext context) => [
      IconButton(
        tooltip: 'Logg ut',
        icon: const Icon(Icons.logout),
        onPressed: () => signOutFromPortal(context),
      ),
    ];

/// Begrenset portal for [UserProfile] som er knyttet til en samarbeidspartner.
/// Versjonsmerke — synlig for bil-eier når ny portal er lastet.
const kOwnerPortalBuildLabel = 'Bil-eier v8';
const kDriverPortalBuildLabel = 'Sjåfør v5';

class PartnerShell extends StatefulWidget {
  final UserProfile profile;
  /// `owner` | `driver` fra [PartnerService.resolvePortalSession].
  final String? portalAccountKind;
  final int initialTabIndex;

  const PartnerShell({
    super.key,
    required this.profile,
    this.portalAccountKind,
    this.initialTabIndex = 0,
  });

  @override
  State<PartnerShell> createState() => _PartnerShellState();
}

class _PartnerShellState extends State<PartnerShell> with WidgetsBindingObserver {
  int _index = 0;
  late UserProfile _profile;
  Partner? _partner;
  bool _loading = true;
  bool _workforceEnabled = false;
  bool _staffCanManageRoutes = false;
  Set<String> _staffRouteVehicleIds = {};
  OwnerPortalRoutesFocus? _routesFocus;
  RealtimeChannel? _workforceChannel;
  StreamSubscription<PushNavigationTarget>? _pushNavSub;
  StreamSubscription<ChatFlag>? _chatFlagSub;
  StreamSubscription<int>? _chatUnreadSub;
  StreamSubscription<PartnerNavBadgeCounts>? _partnerBadgeSub;
  bool _chatEnabled = true;
  int _chatUnread = 0;
  PartnerNavBadgeCounts _partnerBadges = PartnerNavBadgeCounts.zero;

  bool _staffWantsPush() =>
      widget.portalAccountKind == 'staff' &&
      _workforceEnabled &&
      _staffCanManageRoutes;

  bool _wantsPushRegistration() =>
      widget.portalAccountKind == 'driver' ||
      widget.portalAccountKind == 'owner' ||
      _staffWantsPush();

  Future<void> _ensurePushRegistrationIfNeeded() async {
    if (!mounted || !_wantsPushRegistration()) return;
    await NativePermissionsService.ensureNotifications(context: context);
    if (!mounted) return;
    await PushNotificationService.syncRegistration();
  }

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    WidgetsBinding.instance.addObserver(this);
    _index = widget.initialTabIndex;
    _pushNavSub = PushNavigationService.onTarget.listen((target) {
      unawaited(_handlePushNavigation(target));
    });
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncUrl());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await NativePermissionsService.bootstrapAfterLogin(context);
      if (!mounted) return;
      await NativePermissionsService.promptNotificationsIfNeeded(context);
      if (!mounted) return;
      await _ensurePushRegistrationIfNeeded();
    });
  }

  @override
  void didUpdateWidget(PartnerShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id) {
      _profile = widget.profile;
    }
  }

  void _onProfileUpdated(UserProfile profile) {
    setState(() => _profile = profile);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_pushNavSub?.cancel() ?? Future.value());
    unawaited(_chatFlagSub?.cancel() ?? Future.value());
    unawaited(_chatUnreadSub?.cancel() ?? Future.value());
    unawaited(_partnerBadgeSub?.cancel() ?? Future.value());
    ChatUnreadService.stopWatching();
    PartnerNavBadgeService.stop();
    ChatRealtimeNotificationService.stop();
    unawaited(_workforceChannel?.unsubscribe() ?? Future.value());
    PartnerRoutePushListener.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshWorkforceFlag());
      unawaited(ChatUnreadService.refresh());
      unawaited(PartnerNavBadgeService.refresh());
      if (_wantsPushRegistration()) {
        unawaited(PushNotificationService.syncRegistration());
      }
    }
  }

  void _startPartnerPushListener() {
    final pid = widget.profile.partnerId;
    if (pid == null) return;
    if (widget.portalAccountKind == 'driver') {
      PartnerRoutePushListener.start(
        partnerId: pid,
        partnerVehicleId: widget.profile.partnerVehicleId,
      );
      return;
    }
    if (widget.portalAccountKind == 'owner') {
      PartnerRoutePushListener.start(partnerId: pid);
      return;
    }
    // Staff med rutetilgang: rute-push kun for samme partner (GDPR).
    if (widget.portalAccountKind == 'staff' &&
        _workforceEnabled &&
        _staffCanManageRoutes) {
      PartnerRoutePushListener.start(
        partnerId: pid,
        allowedVehicleIds: _staffRouteVehicleIds,
      );
    }
  }

  void _listenWorkforceFlag(String partnerId) {
    unawaited(_workforceChannel?.unsubscribe() ?? Future.value());
    final client = Supabase.instance.client;
    final companyId = _partner?.companyId ?? widget.profile.companyId;
    var channel = client.channel('partner_workforce_dock_$partnerId');
    channel = channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'partners',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: partnerId,
      ),
      callback: (_) => unawaited(_refreshWorkforceFlag()),
    );
    if (companyId != null && companyId.isNotEmpty) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'companies',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: companyId,
        ),
        callback: (_) => unawaited(_refreshWorkforceFlag()),
      );
    }
    final uid = client.auth.currentUser?.id;
    if (widget.portalAccountKind == 'staff' && uid != null) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'partner_staff',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'profile_id',
          value: uid,
        ),
        callback: (_) => unawaited(_refreshWorkforceFlag()),
      );
    }
    _workforceChannel = channel.subscribe();
  }

  Future<void> _refreshWorkforceFlag() async {
    final pid = widget.profile.partnerId;
    if (pid == null || !mounted) return;
    try {
      final enabled = await PartnerWorkforceService.isEnabled(pid);
      var staffRoutes = _staffCanManageRoutes;
      var staffVehicleIds = _staffRouteVehicleIds;
      if (widget.portalAccountKind == 'staff') {
        try {
          final me = await PartnerWorkforceService.myStaffRecord();
          staffRoutes = me?.canManageRoutes == true && enabled;
          staffVehicleIds = me?.routeVehicleIds.toSet() ?? {};
        } catch (_) {
          staffRoutes = false;
          staffVehicleIds = {};
        }
      }
      if (!mounted) return;
      if (enabled == _workforceEnabled &&
          staffRoutes == _staffCanManageRoutes &&
          staffVehicleIds.length == _staffRouteVehicleIds.length &&
          staffVehicleIds.containsAll(_staffRouteVehicleIds)) {
        return;
      }
      setState(() {
        _workforceEnabled = enabled;
        _staffCanManageRoutes = staffRoutes;
        _staffRouteVehicleIds = staffVehicleIds;
        // Hold indeks innenfor synlige faner når Ansatte/Timer/Stempling forsvinner.
        final maxIdx = _visibleTabCount() - 1;
        if (_index > maxIdx) _index = maxIdx.clamp(0, 99);
      });
      if (!enabled) PartnerRoutePushListener.stop();
      _startPartnerPushListener();
      unawaited(_ensurePushRegistrationIfNeeded());
      _syncUrl();
    } catch (_) {}
  }

  int _visibleTabCount() {
    if (widget.portalAccountKind == 'staff') {
      var n = 1; // profil
      if (_workforceEnabled) n += 1; // stempling
      if (_workforceEnabled && _staffCanManageRoutes) n += 1; // ruter
      if (_chatEnabled) n += 1; // meldinger
      return n;
    }
    if (widget.portalAccountKind == 'owner') return _chatEnabled ? 6 : 5;
    return _chatEnabled ? 6 : 5; // driver
  }

  List<String> _portalTabSlugs() {
    final isOwner = widget.portalAccountKind == 'owner';
    final isStaff = widget.portalAccountKind == 'staff';
    if (isStaff) {
      return [
        if (_workforceEnabled) 'stempling',
        if (_workforceEnabled && _staffCanManageRoutes) 'ruter',
        if (_chatEnabled) 'meldinger',
        'profil',
      ];
    }
    if (isOwner) {
      return [
        'oversikt',
        'ruter',
        'dokumenter',
        if (_chatEnabled) 'meldinger',
        'mer',
        'profil',
      ];
    }
    return [
      'oversikt',
      'ruter',
      'dokumenter',
      if (_chatEnabled) 'meldinger',
      'fri',
      'profil',
    ];
  }

  int _ownerMoreTabIndex() => _chatEnabled ? 4 : 3;

  Widget _partnerChatPage() {
    return ChatHubGate(
      child: PartnerChatHubScreen(
        profile: widget.profile,
        embedded: true,
      ),
    );
  }

  void _bindChatFlag(String? companyId) {
    unawaited(_chatFlagSub?.cancel() ?? Future.value());
    _chatFlagSub = null;
    if (companyId == null || companyId.isEmpty) return;
    _chatFlagSub = ChatFlagService.watch(companyId).listen((flag) {
      if (!mounted) return;
      final on = flag.partnersEnabled;
      if (on == _chatEnabled) return;
      setState(() {
        final previousSlugs = _portalTabSlugs();
        final currentSlug = (_index >= 0 && _index < previousSlugs.length)
            ? previousSlugs[_index]
            : 'oversikt';
        _chatEnabled = on;
        final nextSlugs = _portalTabSlugs();
        if (currentSlug == 'meldinger' && !on) {
          final fallback = nextSlugs.contains('mer')
              ? 'mer'
              : (nextSlugs.contains('oversikt') ? 'oversikt' : nextSlugs.first);
          _index = nextSlugs.indexOf(fallback).clamp(0, nextSlugs.length - 1);
        } else {
          final mapped = nextSlugs.indexOf(currentSlug);
          _index = mapped >= 0 ? mapped : _index.clamp(0, nextSlugs.length - 1);
        }
      });
      if (on) {
        _bindChatUnread();
        if (widget.profile.partnerId != null) {
          _bindPartnerBadges(widget.profile.partnerId!);
        }
      } else {
        unawaited(_chatUnreadSub?.cancel() ?? Future.value());
        setState(() => _chatUnread = 0);
      }
      _syncUrl();
    });
    if (_chatEnabled) _bindChatUnread();
  }

  void _bindChatUnread() {
    unawaited(_chatUnreadSub?.cancel() ?? Future.value());
    ChatUnreadService.startWatching();
    unawaited(ChatRealtimeNotificationService.start());
    _chatUnreadSub = ChatUnreadService.stream.listen((count) {
      if (!mounted) return;
      setState(() => _chatUnread = count);
    });
    unawaited(ChatUnreadService.refresh());
  }

  void _bindPartnerBadges(String partnerId) {
    unawaited(_partnerBadgeSub?.cancel() ?? Future.value());
    PartnerNavBadgeService.start(
      partnerId: partnerId,
      partnerVehicleId: widget.profile.partnerVehicleId,
      chatEnabled: _chatEnabled,
    );
    _partnerBadgeSub = PartnerNavBadgeService.stream.listen((counts) {
      if (!mounted) return;
      setState(() {
        _partnerBadges = counts;
        _chatUnread = counts.chat;
      });
    });
    unawaited(PartnerNavBadgeService.refresh());
  }

  PartnerPortalNavItem _chatNavItem() {
    return PartnerPortalNavItem(
      icon: Icons.forum_outlined,
      selectedIcon: Icons.forum,
      label: 'Meldinger',
      badgeCount: _partnerBadges.chat,
    );
  }

  PartnerPortalNavItem _portalNavItem({
    required IconData icon,
    required IconData selectedIcon,
    required String label,
  }) {
    return PartnerPortalNavItem(
      icon: icon,
      selectedIcon: selectedIcon,
      label: label,
      badgeCount: _partnerBadges.forLabel(label),
    );
  }

  void _syncUrl() {
    if (!mounted) return;
    final slugs = _portalTabSlugs();
    if (slugs.isEmpty) return;
    RouteUrlSync.syncTab(
      context,
      basePath: AppPaths.portal,
      index: _index.clamp(0, slugs.length - 1),
      slugs: slugs,
    );
  }

  Future<void> _handlePushNavigation(PushNavigationTarget? target) async {
    if (target == null || !mounted) return;

    if (target.kind == PushNavKind.chatMessage) {
      final roomId = target.id;
      if (roomId != null) ChatPendingNavigation.setRoom(roomId);
      final slugs = _portalTabSlugs();
      final tabIndex = RouteUrlSync.indexForSlug('meldinger', slugs);
      if (tabIndex >= 0 && _index != tabIndex) {
        setState(() => _index = tabIndex);
        _syncUrl();
      }
      PushNavigationService.takePending();
      return;
    }

    if (!target.isPartnerScope) return;
    final partner = _partner;
    if (partner == null) return;

    final tab = target.portalTab;
    if (tab != null) {
      final slugs = _portalTabSlugs();
      final tabIndex = RouteUrlSync.indexForSlug(tab, slugs);
      if (_index != tabIndex) {
        setState(() => _index = tabIndex);
        _syncUrl();
      }
    }

    PushNavigationService.takePending();
    await PartnerPushNavigation.open(
      context,
      target: target,
      partner: partner,
      portalAccountKind: widget.portalAccountKind,
    );
  }

  void _selectTab(int i) {
    setState(() => _index = i);
    _syncUrl();
    // Oppdater feature-flag når eier åpner Mer (Ansatte/Timer synlighet).
    if (widget.portalAccountKind == 'owner' && i == _ownerMoreTabIndex()) {
      unawaited(_refreshWorkforceFlag());
    }
  }

  Future<void> _load() async {
    final pid = widget.profile.partnerId;
    if (pid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      await PartnerPortalScope.assertAccess(
        partnerId: pid,
        partnerVehicleId: widget.profile.partnerVehicleId,
      );
      final p = await PartnerService.fetchPartner(pid);
      var workforce = false;
      var staffRoutes = false;
      var staffVehicleIds = _staffRouteVehicleIds;
      try {
        workforce = await PartnerWorkforceService.isEnabled(pid);
      } catch (_) {}
      if (widget.portalAccountKind == 'staff') {
        try {
          final me = await PartnerWorkforceService.myStaffRecord();
          staffRoutes = me?.canManageRoutes == true;
          staffVehicleIds = me?.routeVehicleIds.toSet() ?? {};
        } catch (_) {
          staffRoutes = false;
          staffVehicleIds = {};
        }
      }
      if (!mounted) return;
      setState(() {
        _partner = p;
        _workforceEnabled = workforce;
        _staffCanManageRoutes = staffRoutes && workforce;
        _staffRouteVehicleIds = staffVehicleIds;
        _loading = false;
      });
      _listenWorkforceFlag(pid);
      _bindChatFlag(p?.companyId ?? widget.profile.companyId);
      _bindPartnerBadges(pid);
      _startPartnerPushListener();
      unawaited(_ensurePushRegistrationIfNeeded());
      unawaited(_handlePushNavigation(PushNavigationService.takePending()));
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke åpne portal: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const DriftProLoadingPage();
    }

    if (widget.profile.partnerId == null || _partner == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Partner'),
          actions: _partnerLogoutActions(context),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange),
                const SizedBox(height: 16),
                const Text(
                  'Kontoen er ikke knyttet til en samarbeidspartner ennå.\n'
                  'Be MAVI om å opprette portal på nytt, eller prøv å koble kontoen på nytt.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () async {
                    setState(() => _loading = true);
                    await SupabaseService.ensureSessionLinkedToCompany();
                    final fresh = await SupabaseService.fetchCurrentUserProfile();
                    if (!mounted) return;
                    if (fresh?.partnerId != null) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(builder: (_) => PartnerShell(profile: fresh!)),
                      );
                      return;
                    }
                    setState(() => _loading = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Fant fortsatt ingen partner-kobling.')),
                    );
                  },
                  child: const Text('Koble konto på nytt'),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => signOutFromPortal(context),
                  child: const Text('Logg ut'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final p = _partner!;
    final isOwner = widget.portalAccountKind == 'owner';
    final isStaff = widget.portalAccountKind == 'staff';
    void goToRoutes({int tabIndex = 1, String? vehicleId}) {
      setState(() {
        _index = 1;
        _routesFocus = OwnerPortalRoutesFocus(tabIndex: tabIndex, vehicleId: vehicleId);
      });
      _syncUrl();
    }

    void openTrekk() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OwnerPortalDeductionsPage(partner: p),
        ),
      );
    }

    final pages = isStaff
        ? [
            if (_workforceEnabled)
              StaffPortalPunchPage(partner: p, profile: _profile),
            if (_workforceEnabled && _staffCanManageRoutes)
              OwnerPortalRoutesPage(partner: p, staffPortal: true),
            if (_chatEnabled) _partnerChatPage(),
            PartnerPortalProfilePage(
              profile: _profile,
              roleLabel: !_workforceEnabled
                  ? 'Ansatt (stempling av)'
                  : _staffCanManageRoutes
                      ? 'Ansatt (stempling + ruter)'
                      : 'Ansatt (kun stempling)',
              partnerName: p.name,
              staffPortal: true,
              onProfileUpdated: _onProfileUpdated,
            ),
          ]
        : isOwner
            ? [
                OwnerPortalOverviewPage(
                  partner: p,
                  workforceEnabled: _workforceEnabled,
                  onGoToRoutes: goToRoutes,
                  onGoToTrekk: openTrekk,
                  onGoToDocs: () => _selectTab(2),
                  onGoToMore: () => _selectTab(_ownerMoreTabIndex()),
                  onGoToTimesheet: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => OwnerPortalTimesheetPage(partner: p),
                      ),
                    );
                  },
                ),
                OwnerPortalRoutesPage(
                  partner: p,
                  launchFocus: _routesFocus,
                  onLaunchFocusConsumed: () {
                    if (_routesFocus != null) {
                      setState(() => _routesFocus = null);
                    }
                  },
                ),
                OwnerPortalDocsPage(partner: p),
                if (_chatEnabled) _partnerChatPage(),
                OwnerPortalMorePage(
                  partner: p,
                  profile: _profile,
                  workforceEnabled: _workforceEnabled,
                ),
                PartnerPortalProfilePage(
                  profile: _profile,
                  roleLabel: 'Bil-eier (hele bedriften)',
                  partnerName: p.name,
                  onProfileUpdated: _onProfileUpdated,
                ),
              ]
            : [
                DriverPortalOverviewPage(partner: p, profile: _profile),
                DriverPortalRoutesPage(partner: p, profile: _profile),
                DriverPortalDocsPage(partner: p),
                if (_chatEnabled) _partnerChatPage(),
                DriverPortalFriPage(partner: p, profile: _profile),
                PartnerPortalProfilePage(
                  profile: _profile,
                  roleLabel: 'Sjåfør (MAVI-bil)',
                  partnerName: p.name,
                  onProfileUpdated: _onProfileUpdated,
                ),
              ];
    final ownerNavItems = [
      _portalNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Oversikt'),
      _portalNavItem(icon: Icons.map_outlined, selectedIcon: Icons.map, label: 'Ruter'),
      _portalNavItem(icon: Icons.folder_open_outlined, selectedIcon: Icons.folder_open, label: 'Dokumenter'),
      if (_chatEnabled) _chatNavItem(),
      _portalNavItem(icon: Icons.apps_outlined, selectedIcon: Icons.apps, label: 'Mer'),
      _portalNavItem(icon: Icons.person_outlined, selectedIcon: Icons.person, label: 'Profil'),
    ];

    final staffNavItems = [
      if (_workforceEnabled)
        _portalNavItem(
          icon: Icons.fingerprint_outlined,
          selectedIcon: Icons.fingerprint,
          label: 'Stempling',
        ),
      if (_workforceEnabled && _staffCanManageRoutes)
        _portalNavItem(icon: Icons.map_outlined, selectedIcon: Icons.map, label: 'Ruter'),
      if (_chatEnabled) _chatNavItem(),
      _portalNavItem(icon: Icons.person_outlined, selectedIcon: Icons.person, label: 'Profil'),
    ];

    final driverNavItems = [
      _portalNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Oversikt'),
      _portalNavItem(icon: Icons.map_outlined, selectedIcon: Icons.map, label: 'Ruter'),
      _portalNavItem(icon: Icons.folder_open_outlined, selectedIcon: Icons.folder_open, label: 'Dokumenter'),
      if (_chatEnabled) _chatNavItem(),
      _portalNavItem(icon: Icons.beach_access_outlined, selectedIcon: Icons.beach_access, label: 'Fri'),
      _portalNavItem(icon: Icons.person_outlined, selectedIcon: Icons.person, label: 'Profil'),
    ];

    final pageIndex = _index.clamp(0, pages.length - 1);
    final navItems = isStaff
        ? staffNavItems
        : isOwner
            ? ownerNavItems
            : driverNavItems;
    final navIndex = _index.clamp(0, navItems.length - 1);

    return DriftProBrandedScaffold(
      showBrandBar: !isStaff,
      body: pages[pageIndex],
      bottomNavigationBar: PartnerPortalBottomNav(
        selectedIndex: navIndex,
        onSelected: _selectTab,
        items: navItems,
      ),
    );
  }
}

class _PartnerOverviewPage extends StatelessWidget {
  final Partner partner;
  final bool isOwner;
  const _PartnerOverviewPage({required this.partner, this.isOwner = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(partner.name),
        actions: _partnerLogoutActions(context),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            isOwner ? 'Bil-eier portal — din bedrift' : 'Sjåfør-portal — dine tildelte ruter',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(partner.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          if (partner.orgNumber != null) Text('Org.nr ${partner.orgNumber}', style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          _infoTile(Icons.person_outline, 'Kontakt eier / leder', partner.ownerName ?? '—'),
          _infoTile(Icons.phone_outlined, 'Telefon', partner.phone ?? '—'),
          _infoTile(Icons.email_outlined, 'E-post', partner.email ?? '—'),
          _infoTile(Icons.place_outlined, 'Adresse', [
            partner.address,
            [partner.postalCode, partner.city].whereType<String>().where((e) => e.isNotEmpty).join(' '),
          ].whereType<String>().where((e) => e.isNotEmpty).join('\n').trim().isEmpty
              ? '—'
              : [
                  partner.address,
                  [partner.postalCode, partner.city].whereType<String>().where((e) => e.isNotEmpty).join(' '),
                ].whereType<String>().where((e) => e.isNotEmpty).join('\n')),
          const Divider(height: 32),
          _infoTile(Icons.local_shipping_outlined, 'Registrerte kjøretøy (bedrift)', '${partner.vehicleCountRegistered}'),
          _infoTile(Icons.scale_outlined, 'Nyttelast (kg, oppgitt)', partner.vehicleMaxPayloadKg?.toString() ?? '—'),
          _infoTile(Icons.verified_outlined, 'EU-godkjent (oppgitt)', partner.euApproved == null ? '—' : (partner.euApproved! ? 'Ja' : 'Nei')),
          const Divider(height: 32),
          _infoTile(Icons.event_outlined, 'Neste planlagte møte', partner.nextMeetingAt != null ? _fmt(partner.nextMeetingAt!) : '—'),
          _infoTile(Icons.fact_check_outlined, 'Siste revisjon / audit', partner.lastAuditAt != null ? _dateOnly(partner.lastAuditAt!) : '—'),
          _infoTile(Icons.schedule_outlined, 'Neste revisjon / audit', partner.nextAuditAt != null ? _dateOnly(partner.nextAuditAt!) : '—'),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) => '${d.day}.${d.month}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  static String _dateOnly(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _infoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: DriftProTheme.primaryGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
                Text(value, style: const TextStyle(fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerDocsPage extends StatefulWidget {
  final Partner partner;
  final bool isOwner;
  const _PartnerDocsPage({required this.partner, this.isOwner = true});

  @override
  State<_PartnerDocsPage> createState() => _PartnerDocsPageState();
}

class _PartnerDocsPageState extends State<_PartnerDocsPage> {
  List<PartnerDocument> _docs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = widget.isOwner
        ? await PartnerService.fetchOwnerPortalDocuments(widget.partner.id)
        : await PartnerService.fetchDriverPortalDocuments(widget.partner.id);
    if (mounted) setState(() => _docs = d);
  }

  Future<void> _open(PartnerDocument doc) async {
    final p = doc.storagePath;
    if (p == null || p.isEmpty) return;
    try {
      final url = await PartnerService.getDocumentPdfSignedUrl(p);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunne ikke åpne: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isOwner ? 'Dokumenter (bedrift)' : 'Dokumenter (sjåfør)'),
        actions: _partnerLogoutActions(context),
      ),
      body: _docs.isEmpty
          ? Center(
              child: Text(
                widget.isOwner
                    ? 'Ingen dokumenter delt med bil-eier ennå.'
                    : 'Ingen dokumenter delt med sjåfør ennå.',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final doc = _docs[i];
                return ListTile(
                  tileColor: Theme.of(context).brightness == Brightness.dark ? DriftProTheme.cardDark : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: const Icon(Icons.description_outlined),
                  title: Text(doc.title),
                  subtitle: Text(
                    '${PartnerDocument.documentTypeLabel(doc.documentType)} · '
                    '${doc.fileName ?? doc.storagePath ?? ''}',
                  ),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _open(doc),
                );
              },
            ),
    );
  }
}

class _PartnerRoutesPage extends StatefulWidget {
  final Partner partner;
  final UserProfile profile;
  final bool isOwner;
  const _PartnerRoutesPage({
    required this.partner,
    required this.profile,
    this.isOwner = false,
  });

  @override
  State<_PartnerRoutesPage> createState() => _PartnerRoutesPageState();
}

class _PartnerRoutesPageState extends State<_PartnerRoutesPage> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<PartnerRouteShare> _active = [];
  List<PartnerRouteShare> _history = [];
  Map<String, FleetShiftDefinition> _shifts = {};
  Map<String, PartnerVehicle> _vehiclesById = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final vid = widget.isOwner ? null : widget.profile.partnerVehicleId;
    final all = (!widget.isOwner && widget.partner.routesOwnerOnly)
        ? <PartnerRouteShare>[]
        : await PartnerService.fetchRouteShares(
            widget.partner.id,
            partnerVehicleId: vid,
            sentOnly: true,
          );
    final cid = widget.partner.companyId;
    final shifts = await PartnerService.fetchFleetShifts(cid);
    final shiftMap = {for (final s in shifts) s.id: s};
    Map<String, PartnerVehicle> vehicleMap = {};
    if (widget.isOwner) {
      final vehicles = await PartnerService.fetchVehicles(widget.partner.id);
      vehicleMap = {for (final v in vehicles) v.id: v};
    }
    final active = all.where(_isActivePortalRoute).toList()..sort(_compareRoutesByStartDesc);
    final history = all.where((r) => !_isActivePortalRoute(r)).toList()..sort(_compareRoutesByStartDesc);
    if (mounted) {
      setState(() {
        _active = active;
        _history = history;
        _shifts = shiftMap;
        _vehiclesById = vehicleMap;
        _loading = false;
      });
    }
  }

  String _shiftLabel(PartnerRouteShare r) {
    final id = r.shiftId;
    if (id == null) return '';
    return _shifts[id]?.name ?? '';
  }

  String _startLabel(PartnerRouteShare r) {
    if (r.routeStartAt == null) return '';
    final t = r.routeStartAt!.toLocal();
    return 'Start ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openPdf(PartnerRouteShare r) async {
    await PartnerRoutePdfActions.openPdf(context, r);
  }

  Future<void> _setAck(PartnerRouteShare r, bool accepted) async {
    final noteCtrl = TextEditingController();
    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(accepted ? 'Aksepter rute' : 'Avlys rute'),
        content: TextField(
          controller: noteCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: accepted ? 'Kommentar (valgfritt)' : 'Begrunnelse til MAVI *',
            hintText: accepted ? null : 'F.eks. bil i verksted, sykdom …',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(accepted ? 'Aksepter' : 'Send avlysning')),
        ],
      ),
    );
    if (shouldContinue != true) {
      noteCtrl.dispose();
      return;
    }
    final comment = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (!accepted && comment.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Skriv en begrunnelse når du avlyser ruten.')),
        );
      }
      return;
    }
    try {
      await PartnerService.updateRouteAcknowledgement(
        routeShareId: r.id,
        accepted: accepted,
        comment: comment.isEmpty ? null : comment,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accepted
                  ? 'Ruten er akseptert.'
                  : 'Ruten er avlyst. Begrunnelsen er sendt til MAVI.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke lagre: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    await _load();
  }

  String _ackLabel(PartnerRouteShare r) {
    switch (r.ackStatus) {
      case 'accepted':
        return 'Akseptert';
      case 'rejected':
        return 'Ikke akseptert';
      default:
        return 'Venter svar';
    }
  }

  Color _ackColor(PartnerRouteShare r) {
    switch (r.ackStatus) {
      case 'accepted':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Widget _routeTile(PartnerRouteShare r, {bool showActions = true}) {
    final shift = _shiftLabel(r);
    final start = _startLabel(r);
    final vehicle = r.partnerVehicleId != null ? _vehiclesById[r.partnerVehicleId] : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PartnerRoutePdfActions.ackDot(r, size: 12),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(r.title ?? 'Rute', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                Text(
                  _ackLabel(r),
                  style: TextStyle(fontWeight: FontWeight.w700, color: _ackColor(r), fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (vehicle != null)
              Text(
                'MAVI ${MaviUnitCodes.normalize(vehicle.unitCode)}',
                style: const TextStyle(fontWeight: FontWeight.w800, color: DriftProTheme.primaryGreen),
              ),
            Text(
              'Rutedag: ${DateFormat('EEEE d. MMM yyyy', 'nb').format(_routeCalendarDay(r))}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (shift.isNotEmpty) Text('Skift: $shift'),
            if (start.isNotEmpty)
              Text(
                start,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: DriftProTheme.accentBlue),
              ),
            if ((r.notes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Melding fra MAVI: ${r.notes}', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
            ],
            if ((r.ackComment ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Din tilbakemelding: ${r.ackComment}',
                style: TextStyle(color: Colors.grey.shade800, fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openPdf(r),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Vis rute-PDF'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _openPdf(r),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Last ned'),
                ),
              ],
            ),
            if (showActions && r.requiresAck) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _setAck(r, true),
                      style: FilledButton.styleFrom(backgroundColor: Colors.green),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Aksepter rute'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _setAck(r, false),
                    icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                    label: const Text('Avlys'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isOwner ? 'Alle ruter' : 'Mine ruter'),
        actions: _partnerLogoutActions(context),
        bottom: TabBar(
          controller: _tab,
          tabs: [
            Tab(text: 'Aktive (${_active.length})'),
            Tab(text: 'Historikk (${_history.length})'),
          ],
        ),
      ),
      body: _loading
          ? const DriftProLoadingCenter()
          : RefreshIndicator(
              onRefresh: _load,
              child: DriftProTabView(
                controller: _tab,
                children: [
                  _active.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Text(
                                'Ingen aktive ruter.\nDu får SMS når MAVI tildeler en ny rute.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _active.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _routeTile(_active[i]),
                        ),
                  _history.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Center(child: Text('Ingen tidligere ruter.')),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _history.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _routeTile(_history[i], showActions: false),
                        ),
                ],
              ),
            ),
    );
  }
}

class _PartnerMeetingsPage extends StatefulWidget {
  final Partner partner;
  const _PartnerMeetingsPage({required this.partner});

  @override
  State<_PartnerMeetingsPage> createState() => _PartnerMeetingsPageState();
}

class _PartnerMeetingsPageState extends State<_PartnerMeetingsPage> {
  List<PartnerMeeting> _meetings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await PartnerService.fetchPortalMeetings(widget.partner.id);
    if (mounted) {
      setState(() {
        _meetings = m.where((x) => !x.isArchived).toList();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Møter & audit'),
        actions: _partnerLogoutActions(context),
      ),
      body: _loading
          ? const DriftProLoadingCenter()
          : _meetings.isEmpty
              ? const Center(child: Text('Ingen planlagte møter.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _meetings.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final m = _meetings[i];
                    return ListTile(
                      tileColor: Theme.of(context).brightness == Brightness.dark
                          ? DriftProTheme.cardDark
                          : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      leading: Icon(
                        m.isAudit ? Icons.fact_check_outlined : Icons.event_outlined,
                        color: DriftProTheme.primaryGreen,
                      ),
                      title: Text(m.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${PartnerMeeting.meetingTypeLabel(m.meetingType)}\n'
                        '${DateFormat('d. MMM yyyy HH:mm', 'nb').format(m.scheduledAt.toLocal())}',
                      ),
                      isThreeLine: true,
                      trailing: PartnerStatusBadge(
                        label: PartnerMeeting.statusLabel(m.status),
                        color: DriftProTheme.info,
                      ),
                    );
                  },
                ),
    );
  }
}

class _PartnerInspectionsPage extends StatefulWidget {
  final Partner partner;
  const _PartnerInspectionsPage({required this.partner});

  @override
  State<_PartnerInspectionsPage> createState() => _PartnerInspectionsPageState();
}

class _PartnerInspectionsPageState extends State<_PartnerInspectionsPage> {
  List<PartnerVehicleInspection> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await PartnerService.fetchVehicleInspections(widget.partner.id);
    if (mounted) {
      setState(() {
        _items = list.take(30).toList();
        _loading = false;
      });
    }
  }

  Future<void> _exportPdf(PartnerVehicleInspection ins) async {
    await HmsPdfExportService.runWithFeedback(
      context,
      fileName: VehicleInspectionPdf.fileNameFor(ins),
      generate: () => VehicleInspectionPdf.generate(
        inspection: ins,
        partner: widget.partner,
        inspectorName: ins.inspectedByName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bilkontroll'),
        actions: _partnerLogoutActions(context),
      ),
      body: _loading
          ? const DriftProLoadingCenter()
          : _items.isEmpty
              ? const Center(child: Text('Ingen registrerte bilkontroller ennå.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final ins = _items[i];
                    final label = ins.registrationNumber ?? ins.unitCode ?? 'Bil';
                    return ListTile(
                      tileColor: Theme.of(context).brightness == Brightness.dark
                          ? DriftProTheme.cardDark
                          : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      leading: Icon(
                        ins.hasDeviation ? Icons.warning_amber : Icons.check_circle,
                        color: ins.hasDeviation ? Colors.orange : Colors.green,
                      ),
                      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${ins.stampLine}\n'
                        '${ins.hasDeviation ? (ins.deviationNotes ?? "Avvik registrert") : "OK — ingen avvik"}',
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: 'Last ned PDF-rapport',
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        onPressed: () => _exportPdf(ins),
                      ),
                    );
                  },
                ),
    );
  }
}

class _PartnerFriPage extends StatefulWidget {
  final Partner partner;
  final UserProfile profile;
  const _PartnerFriPage({required this.partner, required this.profile});

  @override
  State<_PartnerFriPage> createState() => _PartnerFriPageState();
}

class _PartnerFriPageState extends State<_PartnerFriPage> {
  List<PartnerFriRequest> _mine = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await PartnerService.fetchFriRequests(partnerId: widget.partner.id);
    final vid = widget.profile.partnerVehicleId;
    if (mounted) {
      setState(() {
        _mine = vid == null ? all : all.where((r) => r.partnerVehicleId == vid).toList();
        _loading = false;
      });
    }
  }

  Future<void> _requestFri() async {
    final reasonCtrl = TextEditingController();
    var date = DateTime.now().add(const Duration(days: 1));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Søk fri'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Dato'),
                subtitle: Text(DateFormat('d. MMM yyyy', 'nb').format(date)),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) setLocal(() => date = d);
                },
              ),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Begrunnelse',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final cid = widget.partner.companyId;
    await PartnerService.createFriRequest(
      companyId: cid,
      partnerId: widget.partner.id,
      partnerVehicleId: widget.profile.partnerVehicleId,
      requestDate: date,
      reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fri-forespørsel sendt. Venter godkjenning fra MAVI.')),
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fri'),
        actions: [
          IconButton(
            tooltip: 'Søk fri',
            onPressed: _requestFri,
            icon: const Icon(Icons.add),
          ),
          ..._partnerLogoutActions(context),
        ],
      ),
      body: _loading
          ? const DriftProLoadingCenter()
          : _mine.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Ingen fri-forespørsler ennå.'),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _requestFri,
                        icon: const Icon(Icons.beach_access),
                        label: const Text('Søk fri'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _mine.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final r = _mine[i];
                    Color c = Colors.orange;
                    if (r.status == 'approved') c = Colors.green;
                    if (r.status == 'rejected') c = Colors.red;
                    return ListTile(
                      tileColor: Theme.of(context).brightness == Brightness.dark
                          ? DriftProTheme.cardDark
                          : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      title: Text(DateFormat('d. MMM yyyy', 'nb').format(r.requestDate)),
                      subtitle: Text(r.reason ?? '—'),
                      trailing: Text(r.status, style: TextStyle(color: c, fontWeight: FontWeight.w700)),
                    );
                  },
                ),
    );
  }
}
