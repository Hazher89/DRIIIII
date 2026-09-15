import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/drive_monitor/drive_monitor_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';
import '../../widgets/driftpro_loading_indicator.dart';
import 'drive_monitor_map_view.dart';
import 'drive_monitor_stats_panel.dart';

/// Avansert hub for leiebil-sporing — live kart, arkiv per dato, enheter.
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
  List<Map<String, dynamic>> _mapSamples = [];
  List<Map<String, dynamic>> _mapEvents = [];
  List<Map<String, dynamic>> _mapSessions = [];

  DateTime _archiveDate = DateTime.now();
  String? _selectedSessionId;
  bool _mapLoading = false;
  bool _archiveLoaded = false;

  final _df = DateFormat('dd.MM.yyyy HH:mm');
  final _day = DateFormat('dd.MM.yyyy');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      if (_tabs.index == 1 && !_archiveLoaded) {
        _archiveLoaded = true;
        unawaited(_loadArchiveMap());
      }
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await SupabaseService.fetchEffectiveUserProfile();
      final cid = profile?.companyId;
      if (cid == null) throw Exception('Fant ikke bedrift.');
      await DriveMonitorService.archivePreviousDays(cid);
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
      await _loadLiveMap();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadLiveMap() async {
    final cid = _profile?.companyId;
    if (cid == null) return;
    setState(() => _mapLoading = true);
    try {
      final payload = await DriveMonitorService.fetchMapPayload(companyId: cid);
      if (!mounted) return;
      setState(() {
        _mapSessions = _asMapList(payload['sessions']);
        _mapSamples = _asMapList(payload['samples']);
        _mapEvents = _asMapList(payload['events']);
        _selectedSessionId = null;
        _mapLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mapLoading = false;
        _error = 'Kart: $e';
      });
    }
  }

  Future<void> _loadArchiveMap() async {
    final cid = _profile?.companyId;
    if (cid == null) return;
    setState(() => _mapLoading = true);
    try {
      final payload = await DriveMonitorService.fetchMapPayload(
        companyId: cid,
        archiveDate: _archiveDate,
        sessionId: _selectedSessionId,
      );
      if (!mounted) return;
      setState(() {
        _mapSessions = _asMapList(payload['sessions']);
        _mapSamples = _asMapList(payload['samples']);
        _mapEvents = _asMapList(payload['events']);
        _mapLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mapLoading = false;
        _error = 'Arkiv: $e';
      });
    }
  }

  Future<void> _loadSessionMap(String sessionId) async {
    final cid = _profile?.companyId;
    if (cid == null) return;
    setState(() {
      _selectedSessionId = sessionId;
      _mapLoading = true;
    });
    try {
      final payload = await DriveMonitorService.fetchMapPayload(
        companyId: cid,
        sessionId: sessionId,
      );
      if (!mounted) return;
      setState(() {
        _mapSessions = _asMapList(payload['sessions']);
        _mapSamples = _asMapList(payload['samples']);
        _mapEvents = _asMapList(payload['events']);
        _mapLoading = false;
        _tabs.index = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _mapLoading = false);
    }
  }

  List<Map<String, dynamic>> _asMapList(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  int get _activeCount =>
      _sessions.where((s) => s['status'] == 'active').length;

  int get _roughToday {
    final now = DateTime.now();
    return _events.where((e) {
      if (e['severity'] != 'rough') return false;
      final d = DateTime.tryParse('${e['recorded_at']}')?.toLocal();
      if (d == null) return false;
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).length;
  }

  Future<void> _addDeviceUser() async {
    final cid = _profile?.companyId;
    if (cid == null) return;

    final unitNameCtrl = TextEditingController();
    final empNoCtrl = TextEditingController();
    final searchCtrl = TextEditingController();
    var mode = 0; // 0 = ny enhet, 1 = eksisterende bruker
    List<Map<String, dynamic>> hits = [];
    String? error;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Legg til sporingsenhet'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Hver enhet har sitt eget navn (f.eks. «Bil 3» eller «iPad lager»). '
                    'Ikke knyttet til MAVI-biler.',
                    style: TextStyle(fontSize: 13, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Ny enhet')),
                      ButtonSegment(value: 1, label: Text('Eksisterende')),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) => setLocal(() => mode = s.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: unitNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Enhetsnavn *',
                      hintText: 'F.eks. Bil 3, Varebil Øst…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  if (mode == 0) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: empNoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Innloggingsnr (ansattnr) *',
                        hintText: 'Unikt nummer for denne enheten',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Standardpassord: 000000 — byttes under Profil.',
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: searchCtrl,
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
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 180,
                      child: ListView.builder(
                        itemCount: hits.length,
                        itemBuilder: (_, i) {
                          final p = hits[i];
                          final already = p['drive_monitor_device'] == true;
                          return ListTile(
                            dense: true,
                            title: Text(p['full_name'] ?? ''),
                            subtitle: Text(
                              '${p['employee_number'] ?? ''} · '
                              '${p['drive_monitor_unit_name'] ?? 'ingen enhet'}',
                            ),
                            trailing: already
                                ? const Text('Allerede', style: TextStyle(fontSize: 11))
                                : const Icon(Icons.add_circle_outline),
                            onTap: already
                                ? null
                                : () async {
                                    final name = unitNameCtrl.text.trim();
                                    if (name.isEmpty) {
                                      setLocal(
                                        () => error = 'Skriv enhetsnavn først',
                                      );
                                      return;
                                    }
                                    await DriveMonitorService.setDeviceUser(
                                      p['id'] as String,
                                      true,
                                      unitName: name,
                                    );
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    await _bootstrap();
                                  },
                          );
                        },
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Lukk'),
            ),
            if (mode == 0)
              FilledButton(
                onPressed: () async {
                  final name = unitNameCtrl.text.trim();
                  final emp = empNoCtrl.text.trim();
                  if (name.isEmpty || emp.isEmpty) {
                    setLocal(() => error = 'Enhetsnavn og innloggingsnr er påkrevd');
                    return;
                  }
                  try {
                    await DriveMonitorService.createTrackingUnit(
                      companyId: cid,
                      unitName: name,
                      employeeNumber: emp,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _bootstrap();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Enhet «$name» opprettet. Innlogging: $emp / 000000',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    setLocal(() => error = '$e');
                  }
                },
                child: const Text('Opprett'),
              ),
          ],
        ),
      ),
    );
    unitNameCtrl.dispose();
    empNoCtrl.dispose();
    searchCtrl.dispose();
  }

  Future<void> _renameDevice(Map<String, dynamic> d) async {
    final ctrl = TextEditingController(
      text: '${d['drive_monitor_unit_name'] ?? d['full_name'] ?? ''}',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Endre enhetsnavn'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Enhetsnavn',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lagre')),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      await DriveMonitorService.renameDeviceUnit(
        d['id'] as String,
        ctrl.text.trim(),
      );
      await _bootstrap();
    }
    ctrl.dispose();
  }

  Future<void> _savePin() async {
    final cid = _profile?.companyId;
    if (cid == null) return;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ny exit-PIN'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'PIN (minst 4 siffer)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lagre')),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().length >= 4) {
      await DriveMonitorService.saveExitPin(cid, ctrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exit-PIN lagret')),
        );
      }
    }
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leiebil-sporing'),
        actions: [
          IconButton(
            tooltip: 'Oppdater',
            onPressed: _loading ? null : _bootstrap,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Live kart'),
            Tab(text: 'Arkiv'),
            Tab(text: 'Sesjoner'),
            Tab(text: 'Enheter'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: DriftProLoadingIndicator())
          : _error != null && _sessions.isEmpty
              ? Center(child: Text(_error!))
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _liveMapTab(),
                    _archiveTab(),
                    _sessionsTab(),
                    _devicesTab(),
                  ],
                ),
    );
  }

  Widget _kpiRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(child: _kpi('Aktive', '$_activeCount', Icons.directions_car)),
          const SizedBox(width: 8),
          Expanded(child: _kpi('Rå i dag', '$_roughToday', Icons.warning_amber)),
          const SizedBox(width: 8),
          Expanded(
            child: _kpi(
              'Punkter',
              '${_mapSamples.length}',
              Icons.timeline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: DriftProTheme.primaryGreen, size: 20),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            Text(label, style: DriftProTheme.bodySm),
          ],
        ),
      ),
    );
  }

  Widget _liveMapTab() {
    return RefreshIndicator(
      onRefresh: () async {
        await _bootstrap();
        await _loadLiveMap();
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _kpiRow(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Live rute med hastighet (farge), rå brems, rå sving, fartsovertredelse og stillstand. '
              'Data lagres lokalt ved nettbrudd og synkes automatisk.',
              style: DriftProTheme.bodySm.copyWith(color: Colors.grey[700]),
            ),
          ),
          const SizedBox(height: 8),
          if (_mapLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DriveMonitorMapView(
                samples: _mapSamples,
                events: _mapEvents,
                height: MediaQuery.sizeOf(context).height * 0.48,
              ),
            ),
          if (_profile?.companyId != null)
            DriveMonitorStatsPanel(
              companyId: _profile!.companyId!,
              devices: _devices,
              sessions: _sessions,
              events: _events,
            ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Aktive sesjoner', style: DriftProTheme.labelLg),
          ),
          ..._mapSessions.map((s) => _sessionTile(s, openOnMap: true)),
          if (_mapEvents.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Hendelser', style: DriftProTheme.labelLg),
            ),
            ..._mapEvents.reversed.take(40).map(_eventTile),
          ],
        ],
      ),
    );
  }

  Widget _archiveTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Velg dato for full rute. Dagens kjøring: ${_day.format(DateTime.now())}. '
          'Live-fanen viser aktive sesjoner + i dag.',
          style: DriftProTheme.bodySm.copyWith(color: Colors.grey[700]),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Arkivdato'),
          subtitle: Text(_day.format(_archiveDate)),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              firstDate: DateTime(2024),
              lastDate: DateTime.now().add(const Duration(days: 1)),
              initialDate: _archiveDate,
            );
            if (d == null) return;
            setState(() {
              _archiveDate = d;
              _selectedSessionId = null;
              _archiveLoaded = true;
            });
            await _loadArchiveMap();
          },
        ),
        FilledButton.icon(
          onPressed: _mapLoading ? null : _loadArchiveMap,
          icon: const Icon(Icons.map_outlined),
          label: Text(_mapLoading ? 'Laster…' : 'Vis arkiv på kart'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _mapLoading
              ? null
              : () async {
                  setState(() {
                    _archiveDate = DateTime.now();
                    _selectedSessionId = null;
                    _archiveLoaded = true;
                  });
                  await _loadArchiveMap();
                },
          icon: const Icon(Icons.today),
          label: const Text('Vis i dag'),
        ),
        const SizedBox(height: 12),
        if (_mapSessions.isNotEmpty)
          DropdownButtonFormField<String>(
            value: _selectedSessionId ?? '',
            decoration: const InputDecoration(labelText: 'Sesjon (valgfritt)'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Alle denne dagen')),
              ..._mapSessions.map((s) {
                final id = '${s['id']}';
                final label = s['vehicle_label'] ?? 'Sesjon';
                return DropdownMenuItem(value: id, child: Text('$label'));
              }),
            ],
            onChanged: (v) async {
              setState(() => _selectedSessionId = (v == null || v.isEmpty) ? null : v);
              await _loadArchiveMap();
            },
          ),
        const SizedBox(height: 12),
        if (_mapLoading)
          const Center(child: CircularProgressIndicator())
        else
          DriveMonitorMapView(
            samples: _mapSamples,
            events: _mapEvents,
            height: MediaQuery.sizeOf(context).height * 0.42,
          ),
        if (_profile?.companyId != null)
          DriveMonitorStatsPanel(
            companyId: _profile!.companyId!,
            devices: _devices,
            sessions: _sessions,
            events: _events,
          ),
        const SizedBox(height: 12),
        Text(
          '${_mapSamples.length} GPS-punkter · ${_mapEvents.length} hendelser · ${_mapSessions.length} sesjoner',
          style: DriftProTheme.bodySm,
        ),
        ..._mapEvents.reversed.take(50).map(_eventTile),
      ],
    );
  }

  Widget _sessionsTab() {
    return RefreshIndicator(
      onRefresh: _bootstrap,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _sessions.length,
        itemBuilder: (_, i) => _sessionTile(_sessions[i], openOnMap: true),
      ),
    );
  }

  Widget _sessionTile(Map<String, dynamic> s, {bool openOnMap = false}) {
    final rough = (s['rough_event_count'] as num?)?.toInt() ?? 0;
    final active = s['status'] == 'active';
    final color = rough > 0
        ? const Color(0xFFDC2626)
        : active
            ? const Color(0xFF15803D)
            : Colors.grey;
    final started = DateTime.tryParse('${s['started_at']}')?.toLocal();
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(Icons.directions_car, color: color),
        ),
        title: Text(s['vehicle_label']?.toString() ?? 'Leiebil'),
        subtitle: Text(
          [
            if (started != null) _df.format(started),
            '${((s['km'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)} km',
            'score ${(s['score'] as num?)?.toStringAsFixed(0) ?? '—'}',
            if (s['max_speed_kmh'] != null)
              'maks ${(s['max_speed_kmh'] as num).toStringAsFixed(0)} km/t',
            active ? 'LIVE' : (s['is_archived'] == true ? 'Arkiv' : 'Avsluttet'),
          ].join(' · '),
        ),
        trailing: openOnMap ? const Icon(Icons.map_outlined) : null,
        onTap: openOnMap
            ? () => _loadSessionMap('${s['id']}')
            : null,
      ),
    );
  }

  Widget _eventTile(Map<String, dynamic> e) {
    final t = DateTime.tryParse('${e['recorded_at']}')?.toLocal();
    final type = '${e['event_type']}';
    return ListTile(
      dense: true,
      leading: Icon(
        Icons.warning_amber,
        color: DriveMonitorMapView.eventColor(type, '${e['severity']}'),
      ),
      title: Text(DriveMonitorMapView.eventLabel(type)),
      subtitle: Text(
        [
          if (t != null) _df.format(t),
          if (e['speed_kmh'] != null)
            '${(e['speed_kmh'] as num).toStringAsFixed(0)} km/t',
          if (e['accel_ms2'] != null)
            '${(e['accel_ms2'] as num).toStringAsFixed(1)} m/s²',
          '${e['severity']}',
        ].join(' · '),
      ),
    );
  }

  Widget _devicesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: _addDeviceUser,
          icon: const Icon(Icons.add_box_outlined),
          label: const Text('Legg til sporingsenhet'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _savePin,
          icon: const Icon(Icons.pin),
          label: const Text('Sett exit-PIN'),
        ),
        const SizedBox(height: 8),
        Text(
          'Enheter logger inn med eget ansattnr. Ved innlogging starter GPS-sporing '
          'automatisk under enhetsnavnet — ikke knyttet til MAVI-biler.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
        ),
        const SizedBox(height: 16),
        ..._devices.map((d) {
          final unit = (d['drive_monitor_unit_name'] as String?)?.trim();
          return Card(
            child: ListTile(
              leading: const Icon(Icons.phone_android_outlined),
              title: Text(
                (unit != null && unit.isNotEmpty) ? unit : (d['full_name'] ?? 'Enhet'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                'Login: ${d['employee_number'] ?? '—'} · ${d['full_name'] ?? ''}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Endre navn',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _renameDevice(d),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                    onPressed: () async {
                      await DriveMonitorService.setDeviceUser(
                        d['id'] as String,
                        false,
                      );
                      await _bootstrap();
                    },
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
