import 'package:flutter/material.dart';

import '../../core/permissions/access_keys.dart';
import '../../core/permissions/partner_access.dart';
import '../../core/permissions/permission_gate.dart';
import '../../core/permissions/user_access.dart';
import '../../core/services/partner/mavi_unit_codes.dart';
import '../../core/services/partner/partner_search.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import '../../models/partner/partner_links.dart';
import '../../models/user_profile.dart';
import 'bulk_partners_screen.dart';
import 'new_partner_screen.dart';
import 'partner_detail_screen.dart';
import 'partner_route_planner_screen.dart';
import 'partner_sms_compose_screen.dart';
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
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _loading = true;
  String? _error;
  UserProfile? _profile;
  bool _showCompaniesTab = true;
  bool _showRoutesTab = true;
  bool _showSmsTab = true;
  int _savedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs?.removeListener(_onTabChanged);
    _tabs?.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    final tabs = _tabs;
    if (tabs == null || tabs.indexIsChanging) return;
    _savedTabIndex = tabs.index;
  }

  bool _canCompaniesList(UserAccess? access) {
    if (access == null) return false;
    return access.canPartnersTab ||
        access.canPartnersMenu ||
        access.canPartnersAdmin ||
        PartnerAccess.canOpenPartnerDetail(access);
  }

  void _syncDashboardTabs(UserProfile? profile) {
    final access = profile?.access;
    final companies = _canCompaniesList(access);
    final routes = access?.canFleetRoutes == true;
    final sms = PartnerAccess.canOpenPartnersModule(access);
    final length = (companies ? 1 : 0) + (routes ? 1 : 0) + (sms ? 1 : 0);

    _showCompaniesTab = companies;
    _showRoutesTab = routes;
    _showSmsTab = sms;

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
  }

  List<PartnerSearchHit> get _searchHits => PartnerSearch.filterAll(
        partners: _partners,
        vehiclesByPartnerId: _vehiclesByPartner,
        query: _searchQuery,
      );

  int get _maviVehicleCount {
    var n = 0;
    for (final list in _vehiclesByPartner.values) {
      n += list
          .where((v) =>
              v.vehicleKind != 'registration' && !MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode))
          .length;
    }
    return n;
  }

  int get _upcomingMeetings =>
      _partners.where((p) => p.nextMeetingAt != null).length;

  int get _withTransportLicense =>
      _partners.where((p) => p.hasTransportLicense).length;

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
      final byPartner = <String, List<PartnerVehicle>>{};
      for (final row in fleet) {
        byPartner.putIfAbsent(row.partner.id, () => []).add(row.vehicle);
      }
      if (mounted) {
        setState(() {
          _profile = profile;
          _syncDashboardTabs(profile);
          _partners = list;
          _vehiclesByPartner = byPartner;
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
      final byPartner = <String, List<PartnerVehicle>>{};
      for (final row in fleet) {
        byPartner.putIfAbsent(row.partner.id, () => []).add(row.vehicle);
      }
      if (mounted) {
        setState(() {
          _partners = list;
          _vehiclesByPartner = byPartner;
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
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: PartnerUi.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(DriftProTheme.radiusLg)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person_add_outlined, color: DriftProTheme.primaryGreen),
                ),
                title: const Text('Registrer én partner'),
                subtitle: const Text('Brreg, MAVI, kjøretøy og sjåfør-portaler'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openNew();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: DriftProTheme.accentBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.playlist_add_outlined, color: DriftProTheme.accentBlue),
                ),
                title: const Text('Masseimport fra Brreg'),
                subtitle: const Text('Lim inn mange org.nr eller navn'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openBulkImport();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tabIndex = _tabs?.index ?? 0;
    final onCompaniesTab = tabIndex == _tabIndexCompanies();
    final onRoutesTab = tabIndex == _tabIndexRoutes();
    final onSmsTab = tabIndex == _tabIndexSms();
    final canRegister = _profile?.access.canPartnersCreate == true ||
        _profile?.access.canPartnersAdmin == true;

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
          if (onCompaniesTab && !onSmsTab && canRegister)
            IconButton(
              tooltip: 'Ny / masseimport',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _openRegisterMenu,
            ),
        ],
      ),
      floatingActionButton: onCompaniesTab && !onSmsTab && canRegister
          ? FloatingActionButton.extended(
              onPressed: _openRegisterMenu,
              icon: const Icon(Icons.add),
              label: const Text('Registrer'),
              backgroundColor: DriftProTheme.primaryGreen,
              elevation: 4,
            )
          : null,
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
                  PartnerSmsComposeScreen(embedded: true),
              ],
            ),
    );
  }

  Widget _buildPartnersList() {
    if (_loading) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator(color: DriftProTheme.primaryGreen)),
        ],
      );
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

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: PartnerHeroBanner(
            title: 'Bedriftsoversikt',
            subtitle: '${_partners.length} registrerte samarbeidspartnere · ${_maviVehicleCount} MAVI-enheter',
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.domain_rounded, color: Colors.white, size: 26),
            ),
          ),
        ),
        if (_partners.isNotEmpty)
          SliverToBoxAdapter(
            child: PartnerKpiStrip(
              items: [
                PartnerKpiItem(
                  label: 'Bedrifter',
                  value: '${_partners.length}',
                  color: DriftProTheme.primaryGreen,
                  icon: Icons.apartment_outlined,
                ),
                PartnerKpiItem(
                  label: 'MAVI-enheter',
                  value: '$_maviVehicleCount',
                  color: DriftProTheme.accentBlue,
                  icon: Icons.local_shipping_outlined,
                ),
                PartnerKpiItem(
                  label: 'Transport-løyve',
                  value: '$_withTransportLicense',
                  color: DriftProTheme.warning,
                  icon: Icons.verified_outlined,
                ),
                PartnerKpiItem(
                  label: 'Planlagt møte',
                  value: '$_upcomingMeetings',
                  color: DriftProTheme.info,
                  icon: Icons.event_outlined,
                ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: PartnerSearchPanel(
            controller: _searchCtrl,
            hint: 'Søk reg.nr, MAVI, telefon, navn, org.nr…',
            onChanged: (v) => setState(() => _searchQuery = v),
            onClear: _searchQuery.isEmpty
                ? null
                : () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
            hintChips: [
              ('Reg.nr', () => _applySearchHint('AB12345')),
              ('MAVI', () => _applySearchHint('M0001')),
              ('Telefon', () => _applySearchHint('Telefon')),
              ('Kontakt', () => _applySearchHint('Kontaktperson')),
            ],
            trailingChip: _searchQuery.isNotEmpty
                ? Chip(
                    label: Text('${_searchHits.length} treff', style: const TextStyle(fontSize: 11)),
                    backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                    visualDensity: VisualDensity.compact,
                  )
                : null,
          ),
        ),
        if (_partners.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: PartnerEmptyState(
              icon: Icons.handshake_outlined,
              title: 'Ingen samarbeidspartnere ennå',
              subtitle: 'Registrer første bedrift med Brreg-oppslag, MAVI og sjåfør-portaler.',
              action: FilledButton.icon(
                onPressed: _openRegisterMenu,
                icon: const Icon(Icons.add),
                label: const Text('Registrer bedrift'),
                style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
              ),
            ),
          )
        else if (_searchQuery.isNotEmpty && _searchHits.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: PartnerEmptyState(
              icon: Icons.search_off_rounded,
              title: 'Ingen treff',
              subtitle: 'Prøv reg.nr, MAVI (NO_O_M0001), telefon eller bedriftsnavn.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final hit = _searchHits[index];
                  return _PartnerListCard(
                    partner: hit.partner,
                    vehicles: hit.vehicles,
                    matchReasons: hit.matchReasons,
                    onTap: () async {
                      if (!PartnerAccess.canOpenPartnerDetail(_profile?.access)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Du har ikke tilgang til bedriftsdetaljer.'),
                          ),
                        );
                        return;
                      }
                      final deleted = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => PartnerDetailScreen(partner: hit.partner),
                        ),
                      );
                      if (deleted == true) {
                        await _load();
                        _routesKey.currentState?.reload();
                      }
                    },
                  );
                },
                childCount: _searchHits.length,
              ),
            ),
          ),
      ],
    );
  }

  void _applySearchHint(String value) {
    _searchCtrl.text = value;
    setState(() => _searchQuery = value);
  }
}

class _PartnerListCard extends StatelessWidget {
  const _PartnerListCard({
    required this.partner,
    required this.vehicles,
    this.matchReasons = const [],
    required this.onTap,
  });

  final Partner partner;
  final List<PartnerVehicle> vehicles;
  final List<String> matchReasons;
  final VoidCallback onTap;

  List<PartnerVehicle> get _maviVehicles => vehicles
      .where((v) =>
          v.vehicleKind != 'registration' && !MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode))
      .toList();

  String get _maviLine {
    final mavi = _maviVehicles.map((v) => MaviUnitCodes.normalize(v.unitCode)).toList();
    if (mavi.isEmpty) return 'Ingen MAVI registrert';
    if (mavi.length <= 3) return mavi.join(' · ');
    return '${mavi.take(3).join(' · ')} +${mavi.length - 3}';
  }

  Color _auditColor(String status) {
    switch (status) {
      case 'ok':
        return DriftProTheme.success;
      case 'avvik':
      case 'utlopt':
        return DriftProTheme.error;
      case 'planlagt':
        return DriftProTheme.warning;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final maviCount = _maviVehicles.length;
    final regCount = vehicles.length - maviCount;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: PartnerUi.surface(context),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.14)),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: DriftProTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        partner.name.isNotEmpty ? partner.name.characters.first.toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(partner.name, style: DriftProTheme.headingSm),
                          if (partner.tradeName != null && partner.tradeName!.isNotEmpty)
                            Text(
                              partner.tradeName!,
                              style: DriftProTheme.caption,
                            ),
                          const SizedBox(height: 6),
                          Text(
                            _maviLine,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: maviCount > 0
                                  ? DriftProTheme.primaryGreen
                                  : PartnerUi.mutedText(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 16, color: PartnerUi.mutedText(context)),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    PartnerStatusBadge(
                      label: '$maviCount MAVI',
                      color: DriftProTheme.primaryGreen,
                      icon: Icons.local_shipping_outlined,
                    ),
                    if (regCount > 0)
                      PartnerStatusBadge(
                        label: '$regCount reg.nr',
                        color: DriftProTheme.accentBlue,
                        icon: Icons.directions_car_outlined,
                      ),
                    if (partner.hasTransportLicense)
                      PartnerStatusBadge(
                        label: 'Løyve ${partner.transportLicenseCount}',
                        color: DriftProTheme.warning,
                        icon: Icons.verified_outlined,
                      ),
                    PartnerStatusBadge(
                      label: partner.auditStatusLabel,
                      color: _auditColor(partner.auditStatus),
                      icon: Icons.fact_check_outlined,
                    ),
                    if (partner.nextMeetingAt != null)
                      PartnerStatusBadge(
                        label: 'Møte ${_fmt(partner.nextMeetingAt!)}',
                        color: DriftProTheme.info,
                        icon: Icons.event_outlined,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  children: [
                    PartnerMetaRow(icon: Icons.badge_outlined, text: partner.orgNumber ?? '—'),
                    PartnerMetaRow(icon: Icons.person_outline, text: partner.ownerName ?? '—'),
                    PartnerMetaRow(icon: Icons.phone_outlined, text: partner.phone ?? '—'),
                  ],
                ),
                if (partner.notes != null && partner.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.sticky_note_2_outlined, size: 16, color: Colors.amber[800]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            partner.notes!.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: DriftProTheme.bodySm.copyWith(fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (matchReasons.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: matchReasons.take(4).map((r) {
                      return Chip(
                        label: Text(r, style: const TextStyle(fontSize: 10)),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.amber.withValues(alpha: 0.18),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fmt(DateTime d) => '${d.day}.${d.month}.${d.year}';
}
