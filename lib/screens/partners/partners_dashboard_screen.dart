import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/config/driftpro_client.dart';
import '../../core/layout/mobile_shell_scaffold.dart';
import '../../core/permissions/partner_access.dart';
import '../../core/permissions/user_access.dart';
import '../../core/routing/app_paths.dart';
import '../../core/routing/route_url_sync.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import '../../models/partner/partner_links.dart';
import '../../models/user_profile.dart';
import 'bulk_partners_screen.dart';
import 'new_partner_screen.dart';
import 'partner_route_planner_screen.dart';
import 'widgets/partner_companies_board.dart';
import 'partner_deduction_hub_screen.dart';
import 'partner_sms_hub_screen.dart';
import 'vehicle_rental_hub_screen.dart';
import 'vehicle_inspection_hub_screen.dart';
import 'widgets/partner_companies_ui.dart';
import 'widgets/partner_ui.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Oversikt over samarbeidspartnere (interne brukere).
class PartnersDashboardScreen extends StatefulWidget {
  const PartnersDashboardScreen({super.key, this.initialTab});

  final String? initialTab;

  @override
  State<PartnersDashboardScreen> createState() => _PartnersDashboardScreenState();
}

class _PartnersDashboardScreenState extends State<PartnersDashboardScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabs;
  final GlobalKey<PartnerRoutePlannerScreenState> _routesKey =
      GlobalKey<PartnerRoutePlannerScreenState>();
  List<Partner> _partners = [];
  Map<String, List<PartnerVehicle>> _vehiclesByPartner = {};
  Map<String, List<PartnerPortalAccount>> _portalAccountsByPartner = {};
  bool _loading = true;
  String? _error;
  UserProfile? _profile;
  bool _showCompaniesTab = true;
  bool _showRoutesTab = true;
  bool _showSmsTab = true;
  bool _showBotTrekkTab = true;
  bool _showRentalTab = true;
  bool _showInspectionTab = true;
  int _savedTabIndex = 0;
  String? _pendingTabSlug;

  List<String> _visibleTabSlugs() {
    final slugs = <String>[];
    if (_showCompaniesTab) slugs.add('bedrifter');
    if (_showRoutesTab) slugs.add('ruter');
    if (_showSmsTab) slugs.add('sms');
    if (_showBotTrekkTab) slugs.add('bot-trekk');
    if (_showRentalTab) slugs.add('utleie');
    if (_showInspectionTab) slugs.add('bilkontroll');
    return slugs;
  }

  void _syncUrl() {
    if (!mounted) return;
    final slugs = _visibleTabSlugs();
    if (slugs.isEmpty || _tabs == null) return;
    RouteUrlSync.syncTab(
      context,
      basePath: AppPaths.partners,
      index: _tabs!.index,
      slugs: slugs,
    );
  }

  @override
  void initState() {
    super.initState();
    _pendingTabSlug = widget.initialTab;
    _load();
  }

  @override
  void dispose() {
    _tabs?.removeListener(_onTabChanged);
    _tabs?.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    final tabs = _tabs;
    if (tabs == null || tabs.indexIsChanging) return;
    _savedTabIndex = tabs.index;
    _syncUrl();
  }

  bool _canCompaniesList(UserAccess? access) {
    if (access == null) return false;
    return access.canPartnersTab ||
        access.canPartnersMenu ||
        access.canPartnersAdmin ||
        PartnerAccess.canOpenPartnerDetail(access);
  }

  bool _canManageVehicleRentals(UserAccess? access) {
    if (access == null) return false;
    return access.canPartnersVehicleRental ||
        access.canPartnerRoutePlanning ||
        access.canPartnersAdmin;
  }

  bool _canApproveVehicleRentals(UserAccess? access) {
    if (access == null) return false;
    return access.canPartnersVehicleRentalApprove || access.canPartnersAdmin;
  }

  void _syncDashboardTabs(UserProfile? profile) {
    final access = profile?.access;
    final companies = _canCompaniesList(access);
    final routes = access?.canPartnerRoutePlanning == true;
    final sms = access?.canPartnersTabSms == true ||
        access?.canPartnersAdmin == true;
    final botTrekk = access?.canPartnersTabBotTrekk == true ||
        access?.canPartnersAdmin == true;
    final rental = _canManageVehicleRentals(access);
    final inspections = access?.canPartnersTabBilkontroll == true ||
        access?.canPartnersAdmin == true ||
        PartnerAccess.canOpenPartnersModule(access);
    final length = (companies ? 1 : 0) +
        (routes ? 1 : 0) +
        (sms ? 1 : 0) +
        (botTrekk ? 1 : 0) +
        (rental ? 1 : 0) +
        (inspections ? 1 : 0);

    _showCompaniesTab = companies;
    _showRoutesTab = routes;
    _showSmsTab = sms;
    _showBotTrekkTab = botTrekk;
    _showRentalTab = rental;
    _showInspectionTab = inspections;

    if (length == 0) {
      _tabs?.removeListener(_onTabChanged);
      _tabs?.dispose();
      _tabs = null;
      return;
    }

    if (_tabs != null && _tabs!.length == length) {
      return;
    }

    _tabs?.removeListener(_onTabChanged);
    _tabs?.dispose();
    final slugs = _visibleTabSlugs();
    if (_pendingTabSlug != null && slugs.isNotEmpty) {
      _savedTabIndex = RouteUrlSync.indexForSlug(_pendingTabSlug, slugs);
      _pendingTabSlug = null;
    }
    final safeIndex = _savedTabIndex.clamp(0, length - 1);
    _tabs = TabController(
      length: length,
      vsync: this,
      initialIndex: safeIndex,
    )..addListener(_onTabChanged);
    _savedTabIndex = safeIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncUrl());
  }

  void _applyPartnerData({
    required List<Partner> list,
    required List<FleetPartnerVehicleRow> fleet,
    required List<PartnerPortalAccount> portalAccounts,
  }) {
    final byPartner = <String, List<PartnerVehicle>>{};
    for (final row in fleet) {
      byPartner.putIfAbsent(row.partner.id, () => []).add(row.vehicle);
    }
    final accountsByPartner = <String, List<PartnerPortalAccount>>{};
    for (final account in portalAccounts) {
      accountsByPartner.putIfAbsent(account.partnerId, () => []).add(account);
    }
    _partners = list;
    _vehiclesByPartner = byPartner;
    _portalAccountsByPartner = accountsByPartner;
  }

  Future<void> _load() async {
    _savedTabIndex = _tabs?.index ?? _savedTabIndex;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      final profile = await SupabaseService.fetchCurrentUserProfile();
      if (!mounted) return;

      setState(() {
        _profile = profile;
        _syncDashboardTabs(profile);
      });

      if (cid == null) {
        setState(() {
          _loading = false;
          _error = 'Fant ikke bedrift for brukeren.';
        });
        return;
      }

      if (!PartnerAccess.canOpenPartnersModule(profile?.access)) {
        setState(() => _loading = false);
        return;
      }

      unawaited(PartnerService.syncPartnerNotificationEmails(cid));

      final results = await Future.wait([
        PartnerService.fetchPartners(companyId: cid),
        PartnerService.fetchCompanyFleet(cid),
        PartnerService.fetchCompanyPortalAccounts(cid),
      ]);

      if (mounted) {
        setState(() {
          _applyPartnerData(
            list: results[0] as List<Partner>,
            fleet: results[1] as List<FleetPartnerVehicleRow>,
            portalAccounts: results[2] as List<PartnerPortalAccount>,
          );
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  /// Oppdater partnerliste uten å nullstille faner (kalles fra ruteplanlegger).
  Future<void> _refreshPartnersOnly() async {
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null || !mounted) return;
      final results = await Future.wait([
        PartnerService.fetchPartners(companyId: cid),
        PartnerService.fetchCompanyFleet(cid),
        PartnerService.fetchCompanyPortalAccounts(cid),
      ]);
      if (mounted) {
        setState(() {
          _applyPartnerData(
            list: results[0] as List<Partner>,
            fleet: results[1] as List<FleetPartnerVehicleRow>,
            portalAccounts: results[2] as List<PartnerPortalAccount>,
          );
        });
      }
    } catch (_) {}
  }

  Future<void> _openNew() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NewPartnerScreen()),
    );
    if (created == true) {
      await _load();
      _routesKey.currentState?.reload();
    }
  }

  Future<void> _openBulkImport() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const BulkPartnersScreen()),
    );
    if (created == true) {
      await _load();
      _routesKey.currentState?.reload();
    }
  }

  Future<void> _openRegisterMenu() async {
    if (_profile?.access.canPartnersCreate != true &&
        _profile?.access.canPartnersAdmin != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Du har ikke tilgang til å opprette partnere.')),
      );
      return;
    }
    await PartnerCompaniesUi.showRegisterHub(
      context,
      onSingle: _openNew,
      onBulkBrreg: _openBulkImport,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_profile != null && !PartnerAccess.canOpenPartnersModule(_profile!.access)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Samarbeidspartnere')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Du har ikke tilgang til samarbeidspartnere-modulen.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final nested = !DriftProClient.isMobile;

    return MobileShellScaffold(
      title: DriftProClient.isMobile ? 'Partnere' : null,
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      // Web: faner ligger i NestedScrollView og skroller med innholdet (ikke fast AppBar).
      bottom: _tabs == null || !DriftProClient.isMobile
          ? null
          : _buildPartnerTabBar(context),
      body: _tabs == null
          ? (_loading
              ? const DriftProLoadingCenter()
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _error ??
                          'Du har ikke tilgang til noen faner i Samarbeidspartnere.\n'
                              'Be superadmin om «Ruter & planlegging» (fleet_ruter) '
                              'eller andre partner-faner.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ))
          : DriftProClient.isMobile
              ? (_loading
                  ? const DriftProLoadingCenter()
                  : _buildPartnerTabView(nestedScroll: false))
              : NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) => [
                    SliverOverlapAbsorber(
                      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                      sliver: SliverAppBar(
                        pinned: false,
                        floating: false,
                        snap: false,
                        toolbarHeight: 0,
                        forceElevated: innerBoxIsScrolled,
                        bottom: _buildPartnerTabBar(context),
                      ),
                    ),
                  ],
                  body: _loading
                      ? const DriftProLoadingCenter()
                      : _buildPartnerTabView(nestedScroll: nested),
                ),
    );
  }

  PreferredSizeWidget _buildPartnerTabBar(BuildContext context) {
    return TabBar(
      controller: _tabs,
      isScrollable: DriftProClient.isMobile,
      tabAlignment: DriftProClient.isMobile ? TabAlignment.start : TabAlignment.fill,
      indicatorColor: DriftProTheme.primaryGreen,
      labelColor: DriftProTheme.primaryGreenDark,
      unselectedLabelColor: PartnerUi.mutedText(context),
      labelStyle: TextStyle(
        fontSize: DriftProClient.isMobile ? 12 : 14,
        fontWeight: FontWeight.w700,
      ),
      tabs: [
        if (_showCompaniesTab)
          Tab(
            icon: Icon(Icons.apartment_outlined, size: DriftProClient.isMobile ? 20 : 18),
            text: 'Bedrifter',
          ),
        if (_showRoutesTab)
          Tab(
            icon: Icon(Icons.route_outlined, size: DriftProClient.isMobile ? 20 : 18),
            text: DriftProClient.isMobile ? 'Ruter' : 'Ruter & planlegging',
          ),
        if (_showSmsTab)
          Tab(
            icon: Icon(Icons.sms_outlined, size: DriftProClient.isMobile ? 20 : 18),
            text: 'SMS',
          ),
        if (_showBotTrekkTab)
          Tab(
            icon: Icon(Icons.gavel_rounded, size: DriftProClient.isMobile ? 20 : 18),
            text: DriftProClient.isMobile ? 'Bot' : 'Bot/Trekk',
          ),
        if (_showRentalTab)
          Tab(
            icon: Icon(Icons.car_rental_outlined, size: DriftProClient.isMobile ? 20 : 18),
            text: DriftProClient.isMobile ? 'Utleie' : 'Utleie av bil',
          ),
        if (_showInspectionTab)
          Tab(
            icon: Icon(Icons.fact_check_outlined, size: DriftProClient.isMobile ? 20 : 18),
            text: DriftProClient.isMobile ? 'Kontroll' : 'Bilkontroll',
          ),
      ],
    );
  }

  Widget _buildPartnerTabView({required bool nestedScroll}) {
    return TabBarView(
      controller: _tabs,
      children: [
        if (_showCompaniesTab)
          RefreshIndicator(
            onRefresh: _load,
            color: DriftProTheme.primaryGreen,
            child: _buildPartnersList(nestedScroll: nestedScroll),
          ),
        if (_showRoutesTab)
          PartnerRoutePlannerScreen(
            key: _routesKey,
            embedded: true,
            nestedScroll: nestedScroll,
            onDataChanged: _refreshPartnersOnly,
          ),
        if (_showSmsTab)
          PartnerSmsHubScreen(
            embedded: true,
            nestedScroll: nestedScroll,
            partners: _partners,
            canManageNotifications: _profile?.access.canNotifications == true,
          ),
        if (_showBotTrekkTab)
          PartnerDeductionHubScreen(
            embedded: true,
            nestedScroll: nestedScroll,
            partners: _partners,
            profile: _profile,
            canManageNotifications: _profile?.access.canNotifications == true,
          ),
        if (_showRentalTab)
          VehicleRentalHubScreen(
            embedded: true,
            nestedScroll: nestedScroll,
            partners: _partners,
            canApproveRentals: _canApproveVehicleRentals(_profile?.access),
            canForceDeleteRentals: _profile?.role == UserRole.superadmin,
          ),
        if (_showInspectionTab)
          VehicleInspectionHubScreen(
            embedded: true,
            nestedScroll: nestedScroll,
            partners: _partners,
          ),
      ],
    );
  }

  Widget _buildPartnersList({bool nestedScroll = false}) {
    if (_loading) {
      return const DriftProLoadingCenter();
    }
    if (_error != null) {
      return ListView(
        children: [
          PartnerEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Kunne ikke laste bedrifter',
            subtitle: _error,
            action: OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Prøv igjen'),
            ),
          ),
        ],
      );
    }

    return PartnerCompaniesBoard(
      partners: _partners,
      vehiclesByPartner: _vehiclesByPartner,
      portalAccountsByPartner: _portalAccountsByPartner,
      profile: _profile,
      onRefresh: _load,
      onRegister: _openRegisterMenu,
      nestedScroll: nestedScroll,
    );
  }
}
