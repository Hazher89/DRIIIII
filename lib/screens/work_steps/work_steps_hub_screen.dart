import 'package:flutter/material.dart';

import '../../core/services/work_steps/work_steps_privacy.dart';
import '../../core/services/work_steps/work_steps_service.dart';
import '../../core/theme/app_theme.dart';

/// Hub-oversikt (web/app) for frivillige skritt på jobb — MAVI ansatte.
class WorkStepsHubScreen extends StatefulWidget {
  const WorkStepsHubScreen({super.key});

  @override
  State<WorkStepsHubScreen> createState() => _WorkStepsHubScreenState();
}

class _WorkStepsHubScreenState extends State<WorkStepsHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = true;
  String? _error;
  List<WorkStepsHubRow> _rows = const [];
  WorkStepsSettings? _settings;

  final _nameCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  double _radius = 200;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await WorkStepsService.fetchHubOverview();
      final settings = await WorkStepsService.fetchSettings();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _settings = settings;
        _nameCtrl.text = settings?.workplaceName ?? 'Arbeidssted';
        _latCtrl.text = settings?.workplaceLat?.toString() ?? '';
        _lngCtrl.text = settings?.workplaceLng?.toString() ?? '';
        _radius = (settings?.radiusMeters ?? 200).toDouble();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _saveSettings() async {
    final companyId = _settings?.companyId;
    if (companyId == null || companyId.isEmpty) {
      final fresh = await WorkStepsService.fetchSettings();
      if (fresh == null) return;
      await _persist(fresh.companyId);
      return;
    }
    await _persist(companyId);
  }

  Future<void> _persist(String companyId) async {
    final lat = double.tryParse(_latCtrl.text.trim().replaceAll(',', '.'));
    final lng = double.tryParse(_lngCtrl.text.trim().replaceAll(',', '.'));
    await WorkStepsService.saveSettings(
      WorkStepsSettings(
        companyId: companyId,
        enabled: true,
        workplaceName: _nameCtrl.text.trim().isEmpty
            ? 'Arbeidssted'
            : _nameCtrl.text.trim(),
        workplaceLat: lat,
        workplaceLng: lng,
        radiusMeters: _radius.round(),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Arbeidssted lagret')),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final optedIn = _rows.where((r) => r.consentEnabled).length;
    final stepsToday =
        _rows.fold<int>(0, (sum, r) => sum + r.stepsToday);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Skritt på jobb — hub'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Oversikt'),
            Tab(text: 'Arbeidssted'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _overviewTab(optedIn, stepsToday),
                    _settingsTab(),
                  ],
                ),
    );
  }

  Widget _overviewTab(int optedIn, int stepsToday) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            kWorkStepsHubPurpose,
            style: DriftProTheme.bodySm.copyWith(color: Colors.grey[700]),
          ),
          const SizedBox(height: 8),
          Text(
            kWorkStepsOnlyAtWorkBanner,
            style: DriftProTheme.bodySm.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _kpi('Aktive', '$optedIn', Icons.toggle_on),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _kpi('Skritt i dag', '$stepsToday', Icons.directions_walk),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Ansatte', style: DriftProTheme.labelLg),
          const SizedBox(height: 8),
          ..._rows.map((r) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: r.consentEnabled
                      ? DriftProTheme.primaryGreen.withValues(alpha: 0.15)
                      : Colors.grey.withValues(alpha: 0.15),
                  child: Icon(
                    Icons.directions_walk,
                    color: r.consentEnabled
                        ? DriftProTheme.primaryGreen
                        : Colors.grey,
                  ),
                ),
                title: Text(r.fullName),
                subtitle: Text(
                  [
                    if (r.employeeNumber != null) 'Ansattnr ${r.employeeNumber}',
                    r.consentEnabled ? 'Deltar' : 'Ikke aktiv',
                    'Periode: ${r.stepsPeriod} skritt',
                    if (r.lastSyncedAt != null)
                      'Sist synk: ${r.lastSyncedAt!.toLocal()}',
                  ].join(' · '),
                ),
                trailing: Text(
                  '${r.stepsToday}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: DriftProTheme.primaryGreen),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            Text(label, style: DriftProTheme.bodySm),
          ],
        ),
      ),
    );
  }

  Widget _settingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Sett MAVI arbeidssted. Ansatte kan kun synke skritt innenfor radiusen. '
          'Ingen kontinuerlig sporing — kun sjekk når den ansatte oppdaterer.',
          style: DriftProTheme.bodySm.copyWith(color: Colors.grey[700]),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(labelText: 'Navn på arbeidssted'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _latCtrl,
          decoration: const InputDecoration(
            labelText: 'Breddegrad (lat)',
            hintText: '59.91',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _lngCtrl,
          decoration: const InputDecoration(
            labelText: 'Lengdegrad (lng)',
            hintText: '10.75',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        Text('Radius: ${_radius.round()} m'),
        Slider(
          value: _radius,
          min: 50,
          max: 2000,
          divisions: 39,
          label: '${_radius.round()} m',
          onChanged: (v) => setState(() => _radius = v),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saveSettings,
          child: const Text('Lagre arbeidssted'),
        ),
      ],
    );
  }
}
