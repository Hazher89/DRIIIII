import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/permissions/partner_access.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
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

enum _BoardFilter { all, active, inactive }

enum _BoardSort { nameAsc, maviDesc, maviAsc }

extension on _BoardFilter {
  String get label {
    switch (this) {
      case _BoardFilter.all:
        return 'Alle';
      case _BoardFilter.active:
        return 'Aktive';
      case _BoardFilter.inactive:
        return 'Inaktive';
    }
  }
}

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
  });

  final List<Partner> partners;
  final Map<String, List<PartnerVehicle>> vehiclesByPartner;
  final Map<String, List<PartnerPortalAccount>> portalAccountsByPartner;
  final UserProfile? profile;
  final Future<void> Function() onRefresh;
  final VoidCallback? onRegister;

  @override
  State<PartnerCompaniesBoard> createState() => _PartnerCompaniesBoardState();
}

class _PartnerCompaniesBoardState extends State<PartnerCompaniesBoard> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  _BoardFilter _filter = _BoardFilter.all;
  _BoardSort _sort = _BoardSort.nameAsc;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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
    var list = [..._hits];
    list = list.where((h) {
      switch (_filter) {
        case _BoardFilter.all:
          return true;
        case _BoardFilter.active:
          return h.partner.isActive;
        case _BoardFilter.inactive:
          return !h.partner.isActive;
      }
    }).toList();

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
    if (width >= 1400) return 4;
    if (width >= 1100) return 3;
    if (width >= 700) return 2;
    return 1;
  }

  double _childAspectRatio(double width) {
    final cols = _crossAxisCount(width);
    if (cols >= 4) return 0.78;
    if (cols >= 3) return 0.75;
    if (cols >= 2) return 0.72;
    return 0.68;
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

  Widget _gridPanel(List<PartnerSearchHit> filtered, int maviTotal, double width) {
    final activePartners = widget.partners.where((p) => p.isActive).length;
    final totalSmsPhones = widget.partners
        .map((p) => _smsPhonesForHit(PartnerSearchHit(partner: p, vehicles: widget.vehiclesByPartner[p.id] ?? const [])))
        .fold<int>(0, (sum, list) => sum + list.length);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: PartnerModernPageHeader(
            title: 'Bedrifter',
            subtitle: '${widget.partners.length} bedrifter · $maviTotal MAVI',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_canRegister)
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: PartnerModernUi.textPrimary(context),
                      foregroundColor: PartnerModernUi.surface(context),
                    ),
                    onPressed: _openRegister,
                    icon: const Icon(Icons.add, size: 20),
                  ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: PartnerModernKpiGrid(
            items: [
              ('Bedrifter', '${widget.partners.length}'),
              ('Aktive', '$activePartners'),
              ('MAVI', '$maviTotal'),
              ('SMS-numre', '$totalSmsPhones'),
            ],
          ),
        ),
        if (_showSummaryButton)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: FilledButton.icon(
                onPressed: _openSummaryDispatch,
                icon: const Icon(Icons.outbox_outlined),
                label: const Text('Send ut oppsummeringer'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  backgroundColor: DriftProTheme.primaryGreen,
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
        if (widget.partners.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: PartnerEmptyState(
              icon: Icons.domain_outlined,
              title: 'Ingen bedrifter',
              subtitle: 'Opprett første bedrift med Brreg og MAVI.',
              action: _canRegister
                  ? FilledButton.icon(onPressed: _openRegister, icon: const Icon(Icons.add), label: const Text('Kom i gang'))
                  : null,
            ),
          )
        else if (filtered.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('Ingen treff')),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _crossAxisCount(width),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: _childAspectRatio(width),
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (_canRegister && index == 0) {
                    return PartnerCompanyAddCard(onTap: _openRegister);
                  }
                  final i = _canRegister ? index - 1 : index;
                  final hit = filtered[i];
                  final mavi = _maviCodes(hit);
                  final maviVehicles = hit.vehicles
                      .where(
                        (v) =>
                            v.vehicleKind != 'registration' &&
                            !MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode),
                      )
                      .toList();
                  return PartnerCompanyGridCard(
                    name: hit.partner.name,
                    orgNumber: hit.partner.orgNumber,
                    ownerName: hit.partner.ownerName,
                    maviVehicles: maviVehicles,
                    maviCount: mavi.length,
                    regCount: _regCount(hit),
                    isActive: hit.partner.isActive,
                    routesOwnerOnly: hit.partner.routesOwnerOnly,
                    ownerAccounts: widget.portalAccountsByPartner[hit.partner.id]
                            ?.where((a) => a.isOwner)
                            .length ??
                        0,
                    driverAccounts: widget.portalAccountsByPartner[hit.partner.id]
                            ?.where((a) => a.isDriver)
                            .length ??
                        0,
                    smsPhones: _smsPhonesForHit(hit),
                    onTap: () => _openCompany(hit.partner),
                  );
                },
                childCount: filtered.length + (_canRegister ? 1 : 0),
              ),
            ),
          ),
      ],
    );
  }

  Widget _filterSortBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _BoardFilter.values.map((f) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(f.label, style: const TextStyle(fontSize: 11)),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                    visualDensity: VisualDensity.compact,
                    showCheckmark: false,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
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
