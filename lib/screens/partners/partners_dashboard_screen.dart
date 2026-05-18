import 'package:flutter/material.dart';

import '../../core/services/partner/mavi_unit_codes.dart';
import '../../core/services/partner/partner_search.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import '../../models/partner/partner_links.dart';
import 'bulk_partners_screen.dart';
import 'new_partner_screen.dart';
import 'partner_detail_screen.dart';
import 'partner_route_planner_screen.dart';

/// Oversikt over samarbeidspartnere (interne brukere).
class PartnersDashboardScreen extends StatefulWidget {
  const PartnersDashboardScreen({super.key});

  @override
  State<PartnersDashboardScreen> createState() => _PartnersDashboardScreenState();
}

class _PartnersDashboardScreenState extends State<PartnersDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final GlobalKey<PartnerRoutePlannerScreenState> _routesKey =
      GlobalKey<PartnerRoutePlannerScreenState>();
  List<Partner> _partners = [];
  Map<String, List<PartnerVehicle>> _vehiclesByPartner = {};
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<PartnerSearchHit> get _searchHits => PartnerSearch.filterAll(
        partners: _partners,
        vehiclesByPartnerId: _vehiclesByPartner,
        query: _searchQuery,
      );

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) {
        setState(() {
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
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_outlined),
              title: const Text('Registrer én partner'),
              subtitle: const Text('Brreg, MAVI, kjøretøy, portal'),
              onTap: () {
                Navigator.pop(ctx);
                _openNew();
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_outlined),
              title: const Text('Masseimport fra Brreg'),
              subtitle: const Text('Lim inn mange org.nr eller navn'),
              onTap: () {
                Navigator.pop(ctx);
                _openBulkImport();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onCompaniesTab = _tabs.index == 0;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Samarbeidspartnere'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Bedrifter'),
            Tab(text: 'Ruter & planlegging'),
          ],
        ),
        actions: [
          if (!onCompaniesTab)
            IconButton(
              tooltip: 'Oppdater ruteoversikt',
              icon: const Icon(Icons.refresh),
              onPressed: () => _routesKey.currentState?.reload(),
            ),
          if (onCompaniesTab)
            IconButton(
              tooltip: 'Ny / masseimport',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _openRegisterMenu,
            ),
        ],
      ),
      floatingActionButton: onCompaniesTab
          ? FloatingActionButton.extended(
              onPressed: _openRegisterMenu,
              icon: const Icon(Icons.add),
              label: const Text('Registrer'),
              backgroundColor: DriftProTheme.primaryGreen,
            )
          : null,
      body: TabBarView(
        controller: _tabs,
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: _buildPartnersList(),
          ),
          PartnerRoutePlannerScreen(
            key: _routesKey,
            embedded: true,
            onDataChanged: _load,
          ),
        ],
      ),
    );
  }

  Widget _buildPartnersList() {
    if (_loading) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ],
      );
    }
    if (_partners.isEmpty) {
      return ListView(
        children: [
          _buildSearchBar(0),
          const SizedBox(height: 80),
          const Icon(Icons.handshake_outlined, size: 56, color: Colors.grey),
          const SizedBox(height: 16),
          const Center(child: Text('Ingen samarbeidspartnere registrert ennå.')),
        ],
      );
    }
    final hits = _searchHits;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        _buildSearchBar(hits.length),
        const SizedBox(height: 8),
        if (_searchQuery.isNotEmpty && hits.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Ingen treff på «$_searchQuery»\n'
                'Prøv reg.nr, MAVI (NO_O_M0001), telefon eller navn.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          )
        else
          ...hits.map((hit) {
            return _PartnerCard(
              partner: hit.partner,
              vehicles: hit.vehicles,
              matchReasons: hit.matchReasons,
              onTap: () async {
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
          }),
      ],
    );
  }

  Widget _buildSearchBar(int hitCount) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: DriftProTheme.primaryGreen.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Søk: reg.nr, MAVI-nr, telefon, navn, org.nr…',
                prefixIcon: const Icon(Icons.search, color: DriftProTheme.primaryGreen),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _searchHintChip('Reg.nr'),
                _searchHintChip('NO_O_M0001'),
                _searchHintChip('Telefon'),
                _searchHintChip('Kontaktperson'),
                _searchHintChip('Bedrift'),
                if (_searchQuery.isNotEmpty)
                  Chip(
                    label: Text('$hitCount treff', style: const TextStyle(fontSize: 11)),
                    backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchHintChip(String label) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      visualDensity: VisualDensity.compact,
      onPressed: () {
        _searchCtrl.text = label == 'NO_O_M0001' ? 'M0001' : label;
        setState(() => _searchQuery = _searchCtrl.text);
      },
    );
  }
}

class _PartnerCard extends StatelessWidget {
  final Partner partner;
  final List<PartnerVehicle> vehicles;
  final List<String> matchReasons;
  final VoidCallback onTap;

  const _PartnerCard({
    required this.partner,
    required this.vehicles,
    this.matchReasons = const [],
    required this.onTap,
  });

  String get _maviLine {
    if (vehicles.isEmpty) return 'Ingen MAVI registrert';
    return vehicles.map((v) => MaviUnitCodes.normalize(v.unitCode)).join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasMavi = vehicles.isNotEmpty;

    return Card(
      elevation: 0,
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.apartment_rounded, color: DriftProTheme.primaryGreen),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          partner.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _maviLine,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: hasMavi
                                ? DriftProTheme.primaryGreen
                                : Colors.grey[600],
                          ),
                        ),
                        if (partner.orgNumber != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Org.nr ${partner.orgNumber}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                        if (partner.ownerName != null && partner.ownerName!.isNotEmpty)
                          Text(
                            partner.ownerName!,
                            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _mini(Icons.phone_outlined, partner.phone ?? '—'),
                  _mini(Icons.email_outlined, partner.email ?? '—'),
                  if (vehicles.isNotEmpty)
                    _mini(
                      Icons.local_shipping_outlined,
                      vehicles
                          .map((v) => v.registrationNumber)
                          .where((r) =>
                              r.isNotEmpty &&
                              r != MaviUnitCodes.regNrPlaceholder)
                          .join(' · '),
                    ),
                ],
              ),
              if (matchReasons.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: matchReasons.take(4).map((r) {
                    return Chip(
                      label: Text(r, style: const TextStyle(fontSize: 10)),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.amber.withValues(alpha: 0.2),
                    );
                  }).toList(),
                ),
              ],
              if (partner.hasTransportLicense || partner.nextMeetingAt != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (partner.hasTransportLicense)
                      Chip(
                        label: Text(
                          'Transportløyve: ${partner.transportLicenseCount}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (partner.nextMeetingAt != null)
                      Chip(
                        avatar: const Icon(Icons.event, size: 16),
                        label: Text(
                          'Møte ${_fmt(partner.nextMeetingAt!)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _mini(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            text.isEmpty ? '—' : text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.grey[800]),
          ),
        ),
      ],
    );
  }

  static String _fmt(DateTime d) => '${d.day}.${d.month}.${d.year}';
}
