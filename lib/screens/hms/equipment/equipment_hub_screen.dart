import 'package:flutter/material.dart';

import '../../../core/routing/app_paths.dart';
import '../../../core/routing/route_url_sync.dart';
import '../../../core/permissions/user_access.dart';
import '../../../core/services/hms/equipment_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/hms/equipment.dart';
import '../../../models/user_profile.dart';
import 'equipment_detail_screen.dart';
import 'equipment_form_screen.dart';
import 'equipment_service_book_screen.dart';
import 'equipment_truck_profile_screen.dart';
import 'equipment_settings_screen.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Smart utstyrssenter — truck, elektronikk, service, arkiv.
class EquipmentHubScreen extends StatefulWidget {
  const EquipmentHubScreen({super.key, this.initialTab});

  final String? initialTab;

  @override
  State<EquipmentHubScreen> createState() => _EquipmentHubScreenState();
}

class _EquipmentHubScreenState extends State<EquipmentHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  UserProfile? _profile;
  List<Equipment> _all = [];
  List<EquipmentPurchase> _purchases = [];
  Map<String, String> _profileNames = {};
  EquipmentDashboardSummary _summary = const EquipmentDashboardSummary();
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    final idx = RouteUrlSync.indexForSlug(widget.initialTab, AppPaths.equipmentTabs);
    _tabs = TabController(length: 4, vsync: this, initialIndex: idx);
    _tabs.addListener(_onTabChanged);
    _load();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging || !mounted) return;
    RouteUrlSync.syncTab(
      context,
      basePath: AppPaths.hmsUtstyr,
      index: _tabs.index,
      slugs: AppPaths.equipmentTabs,
    );
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _profile = await SupabaseService.fetchCurrentUserProfile();
      final companyId = _profile?.companyId;
      if (companyId == null) return;

      final profiles =
          await SupabaseService.fetchMaviEmployees(companyId: companyId);
      _profileNames = {for (final p in profiles) p.id: p.fullName};

      _all = await EquipmentService.fetchAll(
        companyId: companyId,
        includeRetired: true,
      );
      _purchases =
          await EquipmentService.fetchPurchases(companyId: companyId);
      _summary = EquipmentService.summarize(
        _all.where((e) => e.status != EquipmentStatus.retired).toList(),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  UserAccess? get _access => _profile?.access;

  bool get _canAdmin =>
      _access?.canHmsEquipmentAdmin == true ||
      _profile?.role == UserRole.admin ||
      _profile?.role == UserRole.superadmin;

  bool get _canRegister =>
      _canAdmin || _access?.canHmsEquipmentService == true;

  List<Equipment> get _visible {
    var list = _all.where((e) => e.status != EquipmentStatus.retired);
    if (_access?.dataScopeCompany != true &&
        _access?.canHmsEquipmentAdmin != true) {
      if (_profile != null) {
        list = EquipmentService.filterForEmployee(list.toList(), _profile!)
            .where((e) => e.status != EquipmentStatus.retired);
      }
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((e) {
        return e.name.toLowerCase().contains(q) ||
            (e.serialNumber?.toLowerCase().contains(q) ?? false) ||
            (e.licensePlate?.toLowerCase().contains(q) ?? false);
      });
    }
    return list.toList();
  }

  String? _name(String? id) => id == null ? null : _profileNames[id];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.bgLight,
      appBar: AppBar(
        title: const Text('Maskiner & utstyr'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Oversikt'),
            Tab(text: 'Alle'),
            Tab(text: 'Truck'),
            Tab(text: 'Arkiv'),
          ],
        ),
        actions: [
          if (_canAdmin)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Varsler & innstillinger',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EquipmentSettingsScreen(profile: _profile!),
                  ),
                );
                _load();
              },
            ),
        ],
      ),
      body: _loading
          ? const DriftProLoadingCenter()
          : TabBarView(
              controller: _tabs,
              children: [
                _buildOverview(isDark),
                _buildEquipmentList(isDark, _visible),
                _buildEquipmentList(
                  isDark,
                  _visible
                      .where((e) => e.isTruck)
                      .toList(),
                ),
                _buildArchive(isDark),
              ],
            ),
      floatingActionButton: _canRegister
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text('Registrer'),
              backgroundColor: DriftProTheme.primaryGreen,
            )
          : null,
    );
  }

  Widget _buildOverview(bool isDark) {
    final alerts = _visible.where((e) => e.isOverdue || e.isDueSoon).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _banner(isDark),
          const SizedBox(height: 16),
          _kpiGrid(isDark),
          const SizedBox(height: 24),
          Text('Kommende & forfalt', style: DriftProTheme.headingSm),
          const SizedBox(height: 8),
          if (alerts.isEmpty)
            Text('Ingen varsler akkurat nå.', style: DriftProTheme.caption)
          else
            ...alerts.map((e) => _equipmentTile(e, isDark, highlight: true)),
          const SizedBox(height: 24),
          Text('Mine truck / utstyr', style: DriftProTheme.headingSm),
          const SizedBox(height: 8),
          ..._visible
              .where((e) => e.isTruck)
              .take(5)
              .map((e) => _equipmentTile(e, isDark)),
        ],
      ),
    );
  }

  Widget _banner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blueGrey.shade700,
            DriftProTheme.primaryGreen.withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Smart utstyrssenter',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Kvitteringer · SN · truck-vann · service · arkiv · varsler',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _kpiGrid(bool isDark) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _kpi('Totalt', '${_summary.total}', Icons.inventory_2_outlined),
        _kpi('Truck', '${_summary.trucks}', Icons.local_shipping_outlined),
        _kpi('Elektronikk', '${_summary.electronics}', Icons.devices),
        _kpi('Forfalt', '${_summary.overdue}', Icons.error_outline,
            color: DriftProTheme.error),
        _kpi('Snart', '${_summary.dueSoon}', Icons.schedule,
            color: DriftProTheme.warning),
      ],
    );
  }

  Widget _kpi(String label, String value, IconData icon, {Color? color}) {
    return SizedBox(
      width: 100,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon, color: color ?? DriftProTheme.primaryGreen, size: 22),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(label, style: DriftProTheme.caption, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEquipmentList(bool isDark, List<Equipment> items) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Søk navn, SN, skilt...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: items.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 80),
                      Center(child: Text('Ingen utstyr i denne listen')),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: items.length,
                    itemBuilder: (_, i) =>
                        _equipmentTile(items[i], isDark),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildArchive(bool isDark) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Innkjøpsarkiv', style: DriftProTheme.headingSm),
          const SizedBox(height: 8),
          if (_purchases.isEmpty)
            Text('Ingen innkjøp registrert ennå.', style: DriftProTheme.caption),
          ..._purchases.map((p) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.receipt_long,
                      color: DriftProTheme.primaryGreen),
                  title: Text(p.itemName),
                  subtitle: Text(
                    '${p.purchasedAt.day}.${p.purchasedAt.month}.${p.purchasedAt.year}'
                    '${p.serialNumber != null ? ' · SN: ${p.serialNumber}' : ''}'
                    '${_name(p.assignedToUserId) != null ? '\nTildelt: ${_name(p.assignedToUserId)}' : ''}',
                  ),
                  trailing: p.receiptUrls.isNotEmpty
                      ? const Icon(Icons.attach_file, size: 18)
                      : null,
                ),
              )),
          const SizedBox(height: 24),
          Text('Utrangert utstyr', style: DriftProTheme.headingSm),
          const SizedBox(height: 8),
          ..._all
              .where((e) => e.status == EquipmentStatus.retired)
              .map((e) => _equipmentTile(e, isDark)),
        ],
      ),
    );
  }

  Widget _equipmentTile(Equipment e, bool isDark, {bool highlight = false}) {
    final responsible = _name(e.responsibleUserId);
    final assigned = _name(e.assignedTo);
    Color border = Colors.transparent;
    if (e.isOverdue) border = DriftProTheme.error;
    else if (e.isDueSoon) border = DriftProTheme.warning;
    else if (highlight) border = DriftProTheme.primaryGreen;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border.withValues(alpha: 0.5), width: 2),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: CircleAvatar(
          backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.15),
          child: Icon(
            e.isTruck ? Icons.local_shipping_outlined : Icons.construction,
            color: DriftProTheme.primaryGreen,
          ),
        ),
        title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${e.category.label}${e.serialNumber != null ? ' · SN ${e.serialNumber}' : ''}'),
            if (responsible != null) Text('Ansvarlig: $responsible', style: DriftProTheme.caption),
            if (assigned != null) Text('Bruker: $assigned', style: DriftProTheme.caption),
            if (e.isTruck && e.nextWaterCheck != null)
              Text(
                'Vann: ${e.nextWaterCheck!.day}.${e.nextWaterCheck!.month}.${e.nextWaterCheck!.year}',
                style: DriftProTheme.caption,
              ),
            if (e.nextService != null)
              Text(
                'Service: ${e.nextService!.day}.${e.nextService!.month}.${e.nextService!.year}',
                style: DriftProTheme.caption,
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openDetail(e),
      ),
    );
  }

  Future<void> _openForm({Equipment? edit}) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EquipmentFormScreen(
          profile: _profile!,
          existing: edit,
          profileNames: _profileNames,
        ),
      ),
    );
    if (ok == true) _load();
  }

  Future<void> _openDetail(Equipment e) async {
    if (e.isTruck) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EquipmentTruckProfileScreen(
            equipmentId: e.id,
            profile: _profile!,
            profileNames: _profileNames,
          ),
        ),
      );
      _load();
      return;
    }
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EquipmentDetailScreen(
          equipmentId: e.id,
          profile: _profile!,
          profileNames: _profileNames,
        ),
      ),
    );
    if (ok == true) _load();
  }
}
