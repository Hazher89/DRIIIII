import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/permissions/partner_access.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/partner_summary_service.dart';
import '../../../core/services/partner/partner_search.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../core/permissions/user_access.dart';
import '../../../models/user_profile.dart';
import '../bulk_partners_screen.dart';
import '../new_partner_screen.dart';
import 'partner_companies_ui.dart';
import 'partner_company_grid_card.dart';
import 'partner_company_workspace.dart';
import 'partner_modern_ui.dart';
import 'partner_summary_dispatch_sheet.dart';
import 'partner_ui.dart';

enum _BoardSort { nameAsc, maviDesc, maviAsc }

/// Bedrifts-hub: rutenett av kort — trykk for å redigere.
class PartnerCompaniesBoard extends StatefulWidget {
  const PartnerCompaniesBoard({
    super.key,
    required this.partners,
    required this.vehiclesByPartner,
    required this.portalAccountsByPartner,
    required this.profile,
    required this.onRefresh,
    this.onRegister,
    this.nestedScroll = false,
  });

  final List<Partner> partners;
  final Map<String, List<PartnerVehicle>> vehiclesByPartner;
  final Map<String, List<PartnerPortalAccount>> portalAccountsByPartner;
  final UserProfile? profile;
  final Future<void> Function() onRefresh;
  final VoidCallback? onRegister;
  final bool nestedScroll;

  @override
  State<PartnerCompaniesBoard> createState() => _PartnerCompaniesBoardState();
}

class _PartnerCompaniesBoardState extends State<PartnerCompaniesBoard>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  _BoardSort _sort = _BoardSort.nameAsc;
  late final TabController _listTabs;

  @override
  void initState() {
    super.initState();
    _listTabs = TabController(length: 2, vsync: this);
    _listTabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _listTabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _showingDeactivated => _listTabs.index == 1;

  bool get _canRegister =>
      widget.profile?.access.canPartnersCreate == true || widget.profile?.access.canPartnersAdmin == true;

  /// Alltid synlig på Bedrifter — faktisk sending krever admin/superadmin.
  bool get _showSummaryButton => widget.partners.isNotEmpty;

  String? get _companyId =>
      widget.profile?.companyId ?? widget.partners.firstOrNull?.companyId;

  Future<void> _openSummaryDispatch() async {
    if (!PartnerSummaryService.canManage(widget.profile)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kun administrator kan sende ut oppsummeringer.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final companyId = _companyId;
    if (companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fant ikke bedrift for oppsummeringer.')),
      );
      return;
    }
    final ok = await PartnerSummaryDispatchSheet.show(
      context,
      partners: widget.partners,
      vehiclesByPartner: widget.vehiclesByPartner,
      companyId: companyId,
    );
    if (ok == true) await widget.onRefresh();
  }

  List<PartnerSearchHit> get _hits => PartnerSearch.filterAll(
        partners: widget.partners,
        vehiclesByPartnerId: widget.vehiclesByPartner,
        query: _searchQuery,
      );

  List<PartnerSearchHit> get _filtered {
    var list = _hits.where((h) => _showingDeactivated ? !h.partner.isActive : h.partner.isActive).toList();

    switch (_sort) {
      case _BoardSort.nameAsc:
        list.sort((a, b) => a.partner.name.compareTo(b.partner.name));
        break;
      case _BoardSort.maviDesc:
        list.sort((a, b) => _maviCodes(b).length.compareTo(_maviCodes(a).length));
        break;
      case _BoardSort.maviAsc:
        list.sort((a, b) => _maviCodes(a).length.compareTo(_maviCodes(b).length));
        break;
    }
    return list;
  }

  List<String> _maviCodes(PartnerSearchHit h) => h.vehicles
      .where((v) => v.vehicleKind != 'registration' && !MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode))
      .map((v) => MaviUnitCodes.normalize(v.unitCode))
      .toList();

  int _regCount(PartnerSearchHit h) {
    final maviN = _maviCodes(h).length;
    return h.vehicles.length - maviN;
  }

  int _crossAxisCount(double width) {
    if (width >= 1400) return 3;
    if (width >= 980) return 2;
    return 1;
  }

  Future<void> _openNew() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NewPartnerScreen()),
    );
    if (ok == true) await widget.onRefresh();
  }

  Future<void> _openBulk() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const BulkPartnersScreen()),
    );
    if (ok == true) await widget.onRefresh();
  }

  Future<void> _openRegister() async {
    if (widget.onRegister != null) {
      widget.onRegister!();
      return;
    }
    await PartnerCompaniesUi.showRegisterHub(
      context,
      onSingle: _openNew,
      onBulkBrreg: _openBulk,
    );
  }

  Future<void> _openCompany(Partner partner) async {
    if (!PartnerAccess.canOpenPartnerDetail(widget.profile?.access)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Du har ikke tilgang til bedriftsdetaljer.')),
      );
      return;
    }

    final deleted = await PartnerCompanyWorkspace.open(
      context,
      partner: partner,
      onDataChanged: () => widget.onRefresh(),
    );
    if (deleted == true) await widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final maviTotal = widget.vehiclesByPartner.values
        .expand((l) => l)
        .where((v) => v.vehicleKind != 'registration' && !MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode))
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        return _gridPanel(filtered, maviTotal, constraints.maxWidth);
      },
    );
  }

  Future<void> _activateCompany(Partner partner) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aktiver bedrift?'),
        content: Text('«${partner.name}» får tilbake ruter, SMS og portal-tilgang.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aktiver'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await PartnerService.activatePartnerCompany(partner.id);
      await widget.onRefresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${partner.name} er aktivert')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke aktivere: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _gridPanel(List<PartnerSearchHit> filtered, int maviTotal, double width) {
    final activeCount = widget.partners.where((p) => p.isActive).length;
    final inactiveCount = widget.partners.length - activeCount;
    final totalSmsPhones = widget.partners
        .where((p) => p.isActive)
        .map((p) => _smsPhonesForHit(PartnerSearchHit(partner: p, vehicles: widget.vehiclesByPartner[p.id] ?? const [])))
        .fold<int>(0, (sum, list) => sum + list.length);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (widget.nestedScroll)
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.domain_rounded,
                    color: DriftProTheme.primaryGreenDark,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bedrifter',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: PartnerModernUi.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Hold over eller utvid for detaljer. Trykk for å åpne.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: PartnerModernUi.muted(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _boardChip(
                            context,
                            _showingDeactivated
                                ? '$inactiveCount deaktiverte'
                                : '$activeCount aktive',
                          ),
                          if (!_showingDeactivated)
                            _boardChip(context, '$maviTotal MAVI'),
                          if (!_showingDeactivated)
                            _boardChip(context, '$totalSmsPhones SMS'),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_canRegister)
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: DriftProTheme.primaryGreen,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _openRegister,
                    icon: const Icon(Icons.add, size: 20),
                    tooltip: 'Ny bedrift',
                  ),
              ],
            ),
          ),
        ),
        // KPI-grid fjernet — tall ligger i header-chips.
        SliverToBoxAdapter(
          child: Material(
            color: PartnerModernUi.surface(context),
            child: TabBar(
              controller: _listTabs,
              labelColor: DriftProTheme.primaryGreen,
              tabs: [
                Tab(text: 'Aktive ($activeCount)'),
                Tab(text: 'Deaktiverte ($inactiveCount)'),
              ],
            ),
          ),
        ),
        if (_showSummaryButton && !_showingDeactivated)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _openSummaryDispatch,
                  icon: const Icon(Icons.outbox_outlined, size: 18),
                  label: const Text('Send oppsummeringer'),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: PartnerModernSearchBar(
            controller: _searchCtrl,
            hint: 'Søk bedrift, MAVI, org.nr…',
            onChanged: (v) => setState(() => _searchQuery = v),
            onClear: _searchQuery.isEmpty
                ? null
                : () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
          ),
        ),
        SliverToBoxAdapter(child: _filterSortBar()),
        if (!_showingDeactivated &&
            widget.partners.where((p) => p.isActive).isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: PartnerEmptyState(
              icon: Icons.domain_outlined,
              title: 'Ingen aktive bedrifter',
              subtitle: 'Opprett første bedrift med Brreg og MAVI.',
              action: _canRegister
                  ? FilledButton.icon(
                      onPressed: _openRegister,
                      icon: const Icon(Icons.add),
                      label: const Text('Kom i gang'),
                    )
                  : null,
            ),
          )
        else if (_showingDeactivated && inactiveCount == 0)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Ingen deaktiverte bedrifter'),
              ),
            ),
          )
        else if (filtered.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('Ingen treff')),
          )
        else
          // Intrinsic-height list of cards — ekspandering bryter ikke grid-celler.
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final cols = _crossAxisCount(width);
                  final addTile = _canRegister && !_showingDeactivated;
                  final totalItems =
                      filtered.length + (addTile ? 1 : 0);
                  final rowCount = (totalItems / cols).ceil();
                  if (index >= rowCount) return null;

                  final children = <Widget>[];
                  for (var c = 0; c < cols; c++) {
                    final itemIndex = index * cols + c;
                    if (itemIndex >= totalItems) {
                      children.add(const Expanded(child: SizedBox()));
                      continue;
                    }
                    Widget card;
                    if (addTile && itemIndex == 0) {
                      card = PartnerCompanyAddCard(onTap: _openRegister);
                    } else {
                      final i = addTile ? itemIndex - 1 : itemIndex;
                      final hit = filtered[i];
                      final mavi = _maviCodes(hit);
                      final maviVehicles = hit.vehicles
                          .where(
                            (v) =>
                                v.vehicleKind != 'registration' &&
                                !MaviUnitCodes.isRegistrationOnlyUnit(
                                  v.unitCode,
                                ),
                          )
                          .toList();
                      card = PartnerCompanyGridCard(
                        name: hit.partner.name,
                        orgNumber: hit.partner.orgNumber,
                        ownerName: hit.partner.ownerName,
                        maviVehicles: maviVehicles,
                        maviCount: mavi.length,
                        regCount: _regCount(hit),
                        isActive: hit.partner.isActive,
                        routesOwnerOnly: hit.partner.routesOwnerOnly,
                        ecoDrivingStatus: hit.partner.ecoDrivingStatus,
                        ecoDrivingDeadline: hit.partner.ecoDrivingDeadline,
                        ecoDrivingCompletedAt:
                            hit.partner.ecoDrivingCompletedAt,
                        ownerAccounts: widget
                                .portalAccountsByPartner[hit.partner.id]
                                ?.where((a) => a.isOwner)
                                .length ??
                            0,
                        driverAccounts: widget
                                .portalAccountsByPartner[hit.partner.id]
                                ?.where((a) => a.isDriver)
                                .length ??
                            0,
                        smsPhones: _smsPhonesForHit(hit),
                        onTap: () => _openCompany(hit.partner),
                        onActivate: !hit.partner.isActive
                            ? () => _activateCompany(hit.partner)
                            : null,
                      );
                    }
                    children.add(
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: c < cols - 1 ? 12 : 0,
                            bottom: 12,
                          ),
                          child: card,
                        ),
                      ),
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  );
                },
                childCount:
                    ((filtered.length +
                                ((_canRegister && !_showingDeactivated)
                                    ? 1
                                    : 0)) /
                            _crossAxisCount(width))
                        .ceil(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _boardChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PartnerModernUi.border(context)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: PartnerModernUi.textPrimary(context),
        ),
      ),
    );
  }

  Widget _filterSortBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_showingDeactivated)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Deaktiverte bedrifter får ikke ruter, SMS eller innlogging. Trykk kort for detaljer eller Aktiver.',
                style: TextStyle(fontSize: 11, height: 1.35, color: PartnerModernUi.muted(context)),
              ),
            ),
          Row(
            children: [
              Text('Sorter:', style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context))),
              const SizedBox(width: 8),
              DropdownButton<_BoardSort>(
                value: _sort,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: _BoardSort.nameAsc, child: Text('Navn A–Å', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: _BoardSort.maviDesc, child: Text('Flest MAVI', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: _BoardSort.maviAsc, child: Text('Færrest MAVI', style: TextStyle(fontSize: 12))),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _sort = v);
                },
              ),
              const Spacer(),
              if (_searchQuery.isNotEmpty)
                Text('${_filtered.length} treff', style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context))),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _smsPhonesForHit(PartnerSearchHit hit) {
    final phones = <String>{};
    void addPhone(String? raw) {
      if (raw == null) return;
      final cleaned = raw.trim();
      if (cleaned.isEmpty) return;
      phones.add(cleaned);
    }

    addPhone(hit.partner.phone);
    final accounts = widget.portalAccountsByPartner[hit.partner.id] ?? const <PartnerPortalAccount>[];
    for (final account in accounts) {
      addPhone(account.phone);
    }
    for (final vehicle in hit.vehicles) {
      if (vehicle.isActive) {
        addPhone(vehicle.phone);
      }
    }
    final out = phones.toList()..sort();
    return out;
  }
}
