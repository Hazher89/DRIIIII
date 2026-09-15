import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_paths.dart';
import '../../core/services/work_steps/work_steps_privacy.dart';
import '../../core/services/work_steps/work_steps_service.dart';
import '../../core/theme/app_theme.dart';
import '../../last_mile/services/postal_geocode_service.dart';

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

  bool _savingPlace = false;
  bool _locating = false;

  Future<void> _useMyPosition() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gi tilgang til posisjon for å bruke Min posisjon.')),
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final place = await PostalGeocodeService.reverse(
        lat: pos.latitude,
        lng: pos.longitude,
      );
      if (!mounted || place == null) return;
      setState(() {
        _nameCtrl.text = place.displayName;
        _latCtrl.text = place.lat.toStringAsFixed(6);
        _lngCtrl.text = place.lng.toStringAsFixed(6);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Fant posisjon:\n${place.displayName}\n'
            'Trykk «Lagre arbeidssted» for å bruke dette for alle.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke hente posisjon: $e')),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
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
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skriv inn adresse / navn på arbeidssted.')),
      );
      return;
    }

    var lat = double.tryParse(_latCtrl.text.trim().replaceAll(',', '.'));
    var lng = double.tryParse(_lngCtrl.text.trim().replaceAll(',', '.'));

    setState(() => _savingPlace = true);
    try {
      // Tomme koordinater → finn dem fra adressen automatisk.
      if (lat == null || lng == null) {
        final found = await PostalGeocodeService.resolveAddress(name);
        if (found == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Fant ikke adressen. Skriv mer nøyaktig '
                '(f.eks. «Alf Bjerckes vei 26B, Oslo») eller fyll inn lat/lng.',
              ),
            ),
          );
          return;
        }
        lat = found.lat;
        lng = found.lng;
        _latCtrl.text = lat.toStringAsFixed(6);
        _lngCtrl.text = lng.toStringAsFixed(6);
      }

      await WorkStepsService.saveSettings(
        WorkStepsSettings(
          companyId: companyId,
          enabled: true,
          workplaceName: name,
          workplaceLat: lat,
          workplaceLng: lng,
          radiusMeters: _radius.round(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Arbeidssted lagret: $name '
            '(${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}) · '
            '${_radius.round()} m radius. Alle apper bruker dette.',
          ),
        ),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _savingPlace = false);
    }
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
          TextButton(
            onPressed: () => context.push(AppPaths.moreWorkSteps),
            child: const Text('Mine skritt'),
          ),
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
    final hasCoords = double.tryParse(_latCtrl.text.replaceAll(',', '.')) != null &&
        double.tryParse(_lngCtrl.text.replaceAll(',', '.')) != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Skriv inn adressen og trykk Lagre — systemet finner koordinater. '
          'Eller trykk «Bruk min posisjon» for å fylle adressen der du står nå. '
          'Skritt synkes bare innenfor radiusen. Ingen kontinuerlig sporing.',
          style: DriftProTheme.bodySm.copyWith(color: Colors.grey[700]),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Adresse / navn på arbeidssted',
            hintText: 'Alf Bjerckes vei 26B, Oslo',
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: (_savingPlace || _locating) ? null : _useMyPosition,
          icon: _locating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location),
          label: Text(_locating ? 'Henter posisjon…' : 'Bruk min posisjon'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _latCtrl,
          decoration: const InputDecoration(
            labelText: 'Breddegrad (lat) — fylles automatisk',
            hintText: '59.91',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _lngCtrl,
          decoration: const InputDecoration(
            labelText: 'Lengdegrad (lng) — fylles automatisk',
            hintText: '10.75',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 8),
        Text(
          hasCoords
              ? 'Koordinater er satt — systemet vet hvor jobben er.'
              : 'Koordinater mangler. Lagre med adresse for å finne dem.',
          style: DriftProTheme.bodySm.copyWith(
            color: hasCoords ? DriftProTheme.primaryGreen : Colors.orange[800],
            fontWeight: FontWeight.w600,
          ),
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
          onPressed: _savingPlace ? null : _saveSettings,
          child: Text(_savingPlace ? 'Finner adresse…' : 'Lagre arbeidssted'),
        ),
      ],
    );
  }
}
