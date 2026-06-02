import 'package:flutter/material.dart';

import '../../core/permissions/access_keys.dart';
import '../../core/permissions/partner_access.dart';
import '../../core/permissions/permission_gate.dart';
import '../../core/permissions/user_access.dart';
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
import 'partner_sms_hub_screen.dart';
import 'vehicle_rental_hub_screen.dart';
import 'widgets/partner_companies_ui.dart';
import 'widgets/partner_ui.dart';

/// Oversikt over samarbeidspartnere (interne brukere).
class PartnersDashboardScreen extends StatefulWidget {
  const PartnersDashboardScreen({super.key});

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
  bool _showRentalTab = true;
  int _savedTabIndex = 0;
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
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
    if (mounted) setState(() => _currentTabIndex = tabs.index);
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
        access.canFleetRoutes ||
        access.canPartnersAdmin;
  }

  bool _canApproveVehicleRentals(UserAccess? access) {
    if (access == null) return false;
    return access.canPartnersVehicleRentalApprove || access.canPartnersAdmin;
  }

  void _syncDashboardTabs(UserProfile? profile) {
    final access = profile?.access;
    final companies = _canCompaniesList(access);
    final routes = access?.canFleetRoutes == true;
    final sms = PartnerAccess.canOpenPartnersModule(access);
    final rental = _canManageVehicleRentals(access);
    final length = (companies ? 1 : 0) + (routes ? 1 : 0) + (sms ? 1 : 0) + (rental ? 1 : 0);

    _showCompaniesTab = companies;
    _showRoutesTab = routes;
    _showSmsTab = sms;
    _showRentalTab = rental;

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
    final safeIndex = _savedTabIndex.clamp(0, length - 1);
    _tabs = TabController(
      length: length,
      vsync: this,
      initialIndex: safeIndex,
    )..addListener(_onTabChanged);
    _savedTabIndex = safeIndex;
    _currentTabIndex = safeIndex;
  }

  int _tabIndexCompanies() => _showCompaniesTab ? 0 : -1;

  int _tabIndexRoutes() {
    if (!_showRoutesTab) return -1;
    return _showCompaniesTab ? 1 : 0;
  }

  int _tabIndexSms() {
    if (!_showSmsTab) return -1;
    var i = 0;
    if (_showCompaniesTab) i++;
    if (_showRoutesTab) i++;
    return i;
  }

  void _goToSmsTab() {
    final i = _tabIndexSms();
    if (i < 0 || _tabs == null) return;
    _tabs!.animateTo(i);
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
      if (cid == null) {
        setState(() {
          _profile = profile;
          _syncDashboardTabs(profile);
          _loading = false;
          _error = 'Fant ikke bedrift for brukeren.';
        });
        return;
      }
      final list = await PartnerService.fetchPartners(companyId: cid);
      final fleet = await PartnerService.fetchCompanyFleet(cid);
      final portalAccounts = await PartnerService.fetchCompanyPortalAccounts(cid);
      final byPartner = <String, List<PartnerVehicle>>{};
      for (final row in fleet) {
        byPartner.putIfAbsent(row.partner.id, () => []).add(row.vehicle);
      }
      final accountsByPartner = <String, List<PartnerPortalAccount>>{};
      for (final account in portalAccounts) {
        accountsByPartner.putIfAbsent(account.partnerId, () => []).add(account);
      }
      if (mounted) {
        setState(() {
          _profile = profile;
          _syncDashboardTabs(profile);
          _partners = list;
          _vehiclesByPartner = byPartner;
          _portalAccountsByPartner = accountsByPartner;
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
      final list = await PartnerService.fetchPartners(companyId: cid);
      final fleet = await PartnerService.fetchCompanyFleet(cid);
      final portalAccounts = await PartnerService.fetchCompanyPortalAccounts(cid);
      final byPartner = <String, List<PartnerVehicle>>{};
      for (final row in fleet) {
        byPartner.putIfAbsent(row.partner.id, () => []).add(row.vehicle);
      }
      final accountsByPartner = <String, List<PartnerPortalAccount>>{};
      for (final account in portalAccounts) {
        accountsByPartner.putIfAbsent(account.partnerId, () => []).add(account);
      }
      if (mounted) {
        setState(() {
          _partners = list;
          _vehiclesByPartner = byPartner;
          _portalAccountsByPartner = accountsByPartner;
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
    final tabIndex = _currentTabIndex;
    final onCompaniesTab = _showCompaniesTab && tabIndex == _tabIndexCompanies();
    final onRoutesTab = _showRoutesTab && tabIndex == _tabIndexRoutes();
    final onSmsTab = _showSmsTab && tabIndex == _tabIndexSms();
    final canRegister = _profile?.access.canPartnersCreate == true ||
        _profile?.access.canPartnersAdmin == true;
    final showPartnerRegister = onCompaniesTab && canRegister;

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

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: Text('Samarbeidspartnere', style: DriftProTheme.headingSm),
        bottom: _tabs != null
            ? TabBar(
                controller: _tabs,
                indicatorColor: DriftProTheme.primaryGreen,
                labelColor: DriftProTheme.primaryGreenDark,
                unselectedLabelColor: PartnerUi.mutedText(context),
                tabs: [
                  if (_showCompaniesTab)
                    const Tab(icon: Icon(Icons.apartment_outlined, size: 18), text: 'Bedrifter'),
                  if (_showRoutesTab)
                    const Tab(
                      icon: Icon(Icons.route_outlined, size: 18),
                      text: 'Ruter & planlegging',
                    ),
                  if (_showSmsTab)
                    const Tab(
                      icon: Icon(Icons.sms_outlined, size: 18),
                      text: 'SMS',
                    ),
                  if (_showRentalTab)
                    const Tab(
                      icon: Icon(Icons.car_rental_outlined, size: 18),
                      text: 'Utleie av bil',
                    ),
                ],
              )
            : null,
        actions: [
          if (_showSmsTab && !onSmsTab)
            IconButton(
              tooltip: 'SMS til samarbeidspartnere',
              icon: const Icon(Icons.sms_outlined),
              onPressed: _goToSmsTab,
            ),
          if (onRoutesTab)
            IconButton(
              tooltip: 'Oppdater ruteoversikt',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _routesKey.currentState?.reload(),
            ),
          if (showPartnerRegister)
            IconButton(
              tooltip: 'Ny / masseimport',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _openRegisterMenu,
            ),
        ],
      ),
      body: _tabs == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Du har ikke tilgang til noen faner i Samarbeidspartnere.\n'
                  'Kontakt superadmin.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : TabBarView(
              controller: _tabs,
              children: [
                if (_showCompaniesTab)
                  RefreshIndicator(
                    onRefresh: _load,
                    color: DriftProTheme.primaryGreen,
                    child: _buildPartnersList(),
                  ),
                if (_showRoutesTab)
                  PermissionGuard(
                    profile: _profile,
                    accessKey: AccessKeys.fleetRuter,
                    child: PartnerRoutePlannerScreen(
                      key: _routesKey,
                      embedded: true,
                      onDataChanged: _refreshPartnersOnly,
                    ),
                  ),
                if (_showSmsTab)
                  PartnerSmsHubScreen(
                    embedded: true,
                    partners: _partners,
                  ),
                if (_showRentalTab)
                  VehicleRentalHubScreen(
                    embedded: true,
                    partners: _partners,
                    canApproveRentals: _canApproveVehicleRentals(_profile?.access),
                    canForceDeleteRentals: _profile?.role == UserRole.superadmin,
                  ),
              ],
            ),
    );
  }

  Widget _buildPartnersList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
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
    );
  }
}
