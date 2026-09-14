import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/drive_monitor/drive_monitor_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Oversikt for leiebil-sporing (Mer) — superadmin / tilgang.
class DriveMonitorHubScreen extends StatefulWidget {
  const DriveMonitorHubScreen({super.key});

  @override
  State<DriveMonitorHubScreen> createState() => _DriveMonitorHubScreenState();
}

class _DriveMonitorHubScreenState extends State<DriveMonitorHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  UserProfile? _profile;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _devices = [];
  final _df = DateFormat('dd.MM.yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await SupabaseService.fetchEffectiveUserProfile();
      final cid = profile?.companyId;
      if (cid == null) throw Exception('Fant ikke bedrift.');
      final sessions = await DriveMonitorService.listSessions(companyId: cid);
      final events = await DriveMonitorService.listEvents(companyId: cid);
      final devices = await DriveMonitorService.listDeviceUsers(cid);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _sessions = sessions;
        _events = events;
        _devices = devices;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  int get _activeCount =>
      _sessions.where((s) => s['status'] == 'active').length;
  int get _roughToday {
    final now = DateTime.now();
    return _events.where((e) {
      if (e['severity'] != 'rough') return false;
      final raw = e['recorded_at'];
      if (raw == null) return false;
      final d = DateTime.tryParse('$raw')?.toLocal();
      if (d == null) return false;
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).length;
  }

  double get _avgScore {
    final scored = _sessions
        .where((s) => s['score'] != null)
        .map((s) => (s['score'] as num).toDouble())
        .toList();
    if (scored.isEmpty) return 100;
    return scored.reduce((a, b) => a + b) / scored.length;
  }

  Color _sessionColor(Map<String, dynamic> s) {
    final rough = (s['rough_event_count'] as num?)?.toInt() ?? 0;
    if (s['status'] == 'active') {
      return rough > 0 ? const Color(0xFFDC2626) : const Color(0xFF15803D);
    }
    if (rough > 0) return const Color(0xFFDC2626);
    final score = (s['score'] as num?)?.toDouble() ?? 100;
    if (score < 70) return const Color(0xFFD97706);
    return const Color(0xFF15803D);
  }

  String _sessionStatusLabel(Map<String, dynamic> s) {
    final rough = (s['rough_event_count'] as num?)?.toInt() ?? 0;
    if (s['status'] == 'active') {
      return rough > 0 ? 'Aktiv · rå kjøring' : 'Aktiv · OK';
    }
    if (rough > 0) return 'Arkiv · rå kjøring';
    return 'Arkiv · OK';
  }

  Future<void> _addDeviceUser() async {
    final cid = _profile?.companyId;
    if (cid == null) return;
    final search = TextEditingController();
    List<Map<String, dynamic>> hits = [];
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Legg til sporingsbruker'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Velg en ansatt. Ved innlogging går telefonen automatisk i låst leiebil-sporing.',
                  style: TextStyle(fontSize: 13, height: 1.35),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: search,
                  decoration: const InputDecoration(
                    hintText: 'Søk navn eller ansattnr…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (q) async {
                    hits = await DriveMonitorService.searchEmployees(cid, q);
                    setLocal(() {});
                  },
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 220,
                  child: ListView.builder(
                    itemCount: hits.length,
                    itemBuilder: (_, i) {
                      final p = hits[i];
                      final already = p['drive_monitor_device'] == true;
                      return ListTile(
                        dense: true,
                        title: Text(p['full_name'] ?? ''),
                        subtitle: Text(
                          [
                            if ((p['employee_number'] ?? '').toString().isNotEmpty)
                              'nr ${p['employee_number']}',
                            p['email'] ?? '',
                          ].join(' · '),
                        ),
                        trailing: already
                            ? const Text('Allerede', style: TextStyle(fontSize: 11))
                            : const Icon(Icons.add_circle_outline),
                        onTap: already
                            ? null
                            : () async {
                                await DriveMonitorService.setDeviceUser(
                                  p['id'] as String,
                                  true,
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                await _load();
                              },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Lukk')),
          ],
        ),
      ),
    );
    search.dispose();
  }

  Future<void> _setExitPin() async {
    final cid = _profile?.companyId;
    if (cid == null) return;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hemmelig utgangs-PIN'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Ny PIN (min. 4 siffer)',
            border: OutlineInputBorder(),
            helperText: 'Brukes for å låse opp sporingstelefonen',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lagre')),
        ],
      ),
    );
    if (ok != true) return;
    final pin = ctrl.text.trim();
    if (pin.length < 4) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN må være minst 4 siffer')),
      );
      return;
    }
    await DriveMonitorService.saveExitPin(cid, pin);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Utgangs-PIN lagret')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leiebil-sporing'),
        actions: [
          IconButton(
            tooltip: 'Oppdater',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Oversikt'),
            Tab(text: 'Arkiv'),
            Tab(text: 'Enheter'),
          ],
        ),
      ),
      body: _loading
          ? const DriftProLoadingCenter()
          : _error != null
              ? Center(child: Text(_error!))
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _overviewTab(),
                    _archiveTab(),
                    _devicesTab(),
                  ],
                ),
    );
  }

  Widget _overviewTab() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Row(
            children: [
              Expanded(child: _kpi('Aktive', '$_activeCount', const Color(0xFF15803D))),
              const SizedBox(width: 8),
              Expanded(child: _kpi('Rå i dag', '$_roughToday', const Color(0xFFDC2626))),
              const SizedBox(width: 8),
              Expanded(
                child: _kpi('Snittscore', _avgScore.toStringAsFixed(0), DriftProTheme.primaryGreen),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _legend(),
          const SizedBox(height: 16),
          Text(
            'Siste økter',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: PartnerText.primary(context),
            ),
          ),
          const SizedBox(height: 8),
          if (_sessions.isEmpty)
            Text(
              'Ingen sporingsøkter ennå. Logg inn med en enhetsbruker i bilen for å starte.',
              style: TextStyle(color: Colors.grey.shade700, height: 1.4),
            )
          else
            ..._sessions.take(20).map(_sessionCard),
          const SizedBox(height: 20),
          Text(
            'Siste hendelser',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: PartnerText.primary(context),
            ),
          ),
          const SizedBox(height: 8),
          if (_events.isEmpty)
            Text('Ingen hendelser registrert.', style: TextStyle(color: Colors.grey.shade700))
          else
            ..._events.take(25).map(_eventTile),
        ],
      ),
    );
  }

  Widget _archiveTab() {
    final archived = _sessions.where((s) => s['status'] != 'active').toList();
    if (archived.isEmpty) {
      return const Center(child: Text('Ingen arkiverte økter ennå.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: archived.length,
      itemBuilder: (_, i) => _sessionCard(archived[i]),
    );
  }

  Widget _devicesTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          'Enhetsbrukere logger inn på telefonen i leiebilen. '
          'Appen går da automatisk i låst sporingsmodus.',
          style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade800),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _addDeviceUser,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Legg til bruker'),
          style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _setExitPin,
          icon: const Icon(Icons.pin_outlined),
          label: const Text('Sett hemmelig utgangs-PIN'),
        ),
        const SizedBox(height: 16),
        if (_devices.isEmpty)
          Text(
            'Ingen enhetsbrukere ennå. Ansatt 010101 merkes automatisk hvis kontoen finnes.',
            style: TextStyle(color: Colors.grey.shade700),
          )
        else
          ..._devices.map((d) {
            return Card(
              child: ListTile(
                leading: const Icon(Icons.phone_android),
                title: Text(d['full_name'] ?? ''),
                subtitle: Text(
                  [
                    if ((d['employee_number'] ?? '').toString().isNotEmpty)
                      'nr ${d['employee_number']}',
                    d['email'] ?? '',
                  ].join(' · '),
                ),
                trailing: IconButton(
                  tooltip: 'Fjern',
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                  onPressed: () async {
                    await DriveMonitorService.setDeviceUser(d['id'] as String, false);
                    await _load();
                  },
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _kpi(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  Widget _legend() {
    Widget chip(Color c, String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.withValues(alpha: 0.35)),
          ),
          child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip(const Color(0xFF15803D), 'Grønn = OK'),
        chip(const Color(0xFFD97706), 'Gul = advarsel'),
        chip(const Color(0xFFDC2626), 'Rød = rå kjøring'),
        chip(Colors.blueGrey, 'Bråbrems / hard akselerasjon'),
      ],
    );
  }

  Widget _sessionCard(Map<String, dynamic> s) {
    final color = _sessionColor(s);
    final started = DateTime.tryParse('${s['started_at']}')?.toLocal();
    final ended = DateTime.tryParse('${s['ended_at'] ?? ''}')?.toLocal();
    final label = (s['vehicle_label'] as String?)?.trim().isNotEmpty == true
        ? s['vehicle_label'] as String
        : 'Leiebil';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _sessionStatusLabel(s),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (started != null) _df.format(started),
              if (ended != null) '→ ${_df.format(ended)}',
              'score ${(s['score'] as num?)?.toStringAsFixed(0) ?? '—'}',
              '${((s['km'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)} km',
              '${s['event_count'] ?? 0} hendelser',
            ].join(' · '),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _eventTile(Map<String, dynamic> e) {
    final rough = e['severity'] == 'rough';
    final at = DateTime.tryParse('${e['recorded_at']}')?.toLocal();
    final type = switch (e['event_type']) {
      'hard_brake' => 'Bråbrems',
      'hard_accel' => 'Hard akselerasjon',
      'sharp_turn' => 'Skarp sving',
      'speeding' => 'Høy fart',
      'idle' => 'Stillstand',
      _ => '${e['event_type']}',
    };
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        rough ? Icons.warning_amber_rounded : Icons.info_outline,
        color: rough ? const Color(0xFFDC2626) : const Color(0xFFD97706),
      ),
      title: Text(type, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      subtitle: Text(
        [
          if (at != null) _df.format(at),
          if (e['speed_kmh'] != null)
            '${(e['speed_kmh'] as num).toStringAsFixed(0)} km/t',
        ].join(' · '),
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}

/// Lokal helper for tekstfarge uten å dra inn partner_modern_ui.
abstract final class PartnerText {
  static Color primary(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;
}
