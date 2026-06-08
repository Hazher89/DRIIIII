import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/services/partner/fleet_shift_seed.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/fleet_shift.dart';
import '../../models/partner/partner_links.dart';
import 'widgets/partner_route_pdf_actions.dart';

/// Administrer skift + arkiv med tilhørende rute-PDF-er.
class FleetShiftAdminScreen extends StatefulWidget {
  const FleetShiftAdminScreen({super.key});

  @override
  State<FleetShiftAdminScreen> createState() => _FleetShiftAdminScreenState();
}

class _FleetShiftAdminScreenState extends State<FleetShiftAdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  String? _companyId;
  bool _loading = true;
  List<FleetShiftDefinition> _active = [];
  List<FleetShiftDefinition> _archived = [];
  List<PartnerRouteShare> _archiveRoutes = [];
  String? _selectedArchiveShiftId;

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
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;
      await PartnerService.ensureCanonicalFleetShifts(cid);
      final active = await PartnerService.fetchFleetShifts(cid);
      final archived = await PartnerService.fetchArchivedFleetShifts(cid);
      if (mounted) {
        setState(() {
          _companyId = cid;
          _active = active;
          _archived = archived;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadArchiveRoutes(String shiftId) async {
    final cid = _companyId;
    if (cid == null) return;
    setState(() => _selectedArchiveShiftId = shiftId);
    final routes = await PartnerService.fetchRouteSharesForShift(cid, shiftId);
    if (mounted) setState(() => _archiveRoutes = routes);
  }

  Future<void> _openPdf(PartnerRouteShare share) async {
    await PartnerRoutePdfActions.openPdf(context, share);
  }

  Future<void> _resetCanonical() async {
    final cid = _companyId;
    if (cid == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tilbakestill skift?'),
        content: Text(
          'Arkiverer alle aktive skift og legger inn ${FleetShiftSeed.canonicalNames.length} '
          'standard skift. Gamle PDF-er forblir koblet til arkiverte skift.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bekreft')),
        ],
      ),
    );
    if (ok != true) return;
    await PartnerService.replaceAllFleetShiftsWithCanonical(cid);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Standard skift er lagt inn.')),
      );
    }
    await _load();
  }

  Future<void> _addShift() async {
    final cid = _companyId;
    if (cid == null) return;
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nytt skift'),
        content: TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Navn', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Opprett')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) {
      name.dispose();
      return;
    }
    await PartnerService.createFleetShift(
      companyId: cid,
      name: name.text.trim(),
      colorHex: '#2E7D32',
    );
    name.dispose();
    await _load();
  }

  Future<void> _editShift(FleetShiftDefinition shift) async {
    final name = TextEditingController(text: shift.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rediger skift'),
        content: TextField(
          controller: name,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lagre')),
        ],
      ),
    );
    if (ok != true) {
      name.dispose();
      return;
    }
    await PartnerService.updateFleetShift(shift.id, name: name.text.trim());
    name.dispose();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Skiftadministrasjon'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Aktive skift'),
            Tab(text: 'Arkiv & PDF-er'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _activeTab(),
                _archiveTab(),
              ],
            ),
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton.extended(
              onPressed: _addShift,
              icon: const Icon(Icons.add),
              label: const Text('Nytt skift'),
              backgroundColor: DriftProTheme.primaryGreen,
            )
          : null,
    );
  }

  Widget _activeTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      children: [
        Card(
          color: Colors.amber.withValues(alpha: 0.12),
          child: ListTile(
            leading: const Icon(Icons.restore, color: Colors.amber),
            title: const Text('Tilbakestill til standard skiftliste'),
            subtitle: Text('${FleetShiftSeed.canonicalNames.length} skift fra MAVI-listen'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _resetCanonical,
          ),
        ),
        const SizedBox(height: 8),
        Text('${_active.length} aktive skift', style: DriftProTheme.headingSm),
        const SizedBox(height: 8),
        ..._active.map((s) {
          return Card(
            child: ListTile(
              leading: CircleAvatar(backgroundColor: s.color, radius: 12),
              title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${s.shiftKind == 'availability' ? 'Tilgjengelighet' : 'Rute'} · ${s.regionGroup ?? '—'}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') {
                    await _editShift(s);
                  } else if (v == 'archive') {
                    await PartnerService.archiveFleetShift(s.id);
                    await _load();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Rediger')),
                  PopupMenuItem(value: 'archive', child: Text('Arkiver')),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _archiveTab() {
    return Row(
      children: [
        SizedBox(
          width: 280,
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Gamle skift — velg for å se alle rute-PDF-er',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              if (_archived.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Ingen arkiverte skift ennå.'),
                ),
              ..._archived.map((s) {
                final selected = _selectedArchiveShiftId == s.id;
                return Card(
                  color: selected ? DriftProTheme.primaryGreen.withValues(alpha: 0.1) : null,
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(backgroundColor: s.color, radius: 8),
                    title: Text(s.name, style: const TextStyle(fontSize: 13)),
                    onTap: () => _loadArchiveRoutes(s.id),
                  ),
                );
              }),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _archiveRoutes.isEmpty
              ? const Center(child: Text('Velg et arkivert skift'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _archiveRoutes.length,
                  itemBuilder: (_, i) {
                    final r = _archiveRoutes[i];
                    return ListTile(
                      leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                      title: Text(r.title ?? 'Rute-PDF'),
                      subtitle: Text(
                        DateFormat('d.M.y').format(r.shareDate),
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () => _openPdf(r),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
