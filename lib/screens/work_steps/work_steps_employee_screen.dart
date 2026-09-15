import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/services/work_steps/work_steps_health_bridge.dart';
import '../../core/services/work_steps/work_steps_privacy.dart';
import '../../core/services/work_steps/work_steps_service.dart';
import '../../core/services/work_steps/work_steps_sync.dart';
import '../../core/theme/app_theme.dart';

/// Ansatt-visning: tydelig samtykke, av/på, kun på jobb.
class WorkStepsEmployeeScreen extends StatefulWidget {
  const WorkStepsEmployeeScreen({super.key});

  @override
  State<WorkStepsEmployeeScreen> createState() =>
      _WorkStepsEmployeeScreenState();
}

class _WorkStepsEmployeeScreenState extends State<WorkStepsEmployeeScreen> {
  bool _loading = true;
  bool _busy = false;
  WorkStepsConsent? _consent;
  WorkStepsSettings? _settings;
  List<WorkStepsDaily> _history = const [];
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final consent = await WorkStepsService.fetchMyConsent();
      final settings = await WorkStepsService.fetchSettings();
      final history = await WorkStepsService.fetchMyHistory();
      if (!mounted) return;
      setState(() {
        _consent = consent;
        _settings = settings;
        _history = history;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'Kunne ikke laste: $e';
      });
    }
  }

  Future<void> _showConsentThenEnable() async {
    // Apple/Google: short in-app purpose → then OS permission dialog.
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          icon: Icon(
            Icons.directions_walk,
            color: DriftProTheme.primaryGreen,
            size: 36,
          ),
          title: const Text(kWorkStepsConsentHeadline),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(kWorkStepsConsentBody),
              SizedBox(height: 12),
              Text(
                kWorkStepsConsentDetail,
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Ikke tillat'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tillat'),
            ),
          ],
        );
      },
    );
    if (accepted != true || !mounted) return;

    setState(() => _busy = true);
    try {
      // Native Apple Health / Google Health Connect prompt next.
      if (!kIsWeb && await WorkStepsHealthBridge.isSupported()) {
        final granted = await WorkStepsHealthBridge.requestAuthorization();
        if (!granted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Tillatelse ble ikke gitt. Du kan endre dette i '
                'Apple Helse eller Health Connect.',
              ),
            ),
          );
          setState(() => _busy = false);
          return;
        }
      }
      await WorkStepsService.setConsentEnabled(true);
      await _load();
      if (!mounted) return;
      setState(() =>
          _status = 'Deling er på. Synk virker bare på MAVI arbeidssted.');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke aktivere: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    setState(() => _busy = true);
    try {
      await WorkStepsService.setConsentEnabled(false);
      await _load();
      if (!mounted) return;
      setState(() => _status = 'Skritt på jobb er slått av. Ingen skritt leses.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    setState(() => _busy = true);
    try {
      final result = await WorkStepsSync.syncNow();
      await _load();
      if (!mounted) return;
      setState(() => _status = result.message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slette skrittdata?'),
        content: const Text(
          'Dette sletter dine lagrede skritt-på-jobb-tall i DriftPro. '
          'Apple Helse / Health Connect på telefonen endres ikke.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Slett')),
        ],
      ),
    );
    if (ok != true) return;
    await WorkStepsService.deleteMyStepData();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _consent?.enabled == true;
    final workplace = _settings?.workplaceName ?? 'arbeidssted';

    return Scaffold(
      appBar: AppBar(title: const Text(kWorkStepsFeatureTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    kWorkStepsOnlyAtWorkBanner,
                    style: TextStyle(fontWeight: FontWeight.w700, height: 1.35),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  kWorkStepsShortPurpose,
                  style: DriftProTheme.bodySm.copyWith(color: Colors.grey[700]),
                ),
                const SizedBox(height: 20),
                Card(
                  child: SwitchListTile(
                    title: Text(
                      enabled ? 'Deling er på' : 'Deling er av',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      enabled
                          ? 'Du deler skritt kun når du er på $workplace. Slå av når du vil.'
                          : 'Slått av. DriftPro leser ikke skrittene dine.',
                    ),
                    value: enabled,
                    onChanged: _busy
                        ? null
                        : (v) {
                            if (v) {
                              _showConsentThenEnable();
                            } else {
                              _disable();
                            }
                          },
                  ),
                ),
                if (enabled) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _sync,
                    icon: const Icon(Icons.sync),
                    label: Text(_busy ? 'Jobber…' : 'Oppdater skritt nå'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Oppdatering sjekker én gang at du er på jobb, og leser deretter dagens skritt. '
                    'Ingen kontinuerlig sporing.',
                    style: DriftProTheme.bodySm.copyWith(color: Colors.grey[600]),
                  ),
                ],
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(_status!, style: DriftProTheme.bodySm),
                ],
                const SizedBox(height: 24),
                Text('Mine skritt på jobb', style: DriftProTheme.labelLg),
                const SizedBox(height: 8),
                if (_history.isEmpty)
                  Text(
                    'Ingen lagrede skritt ennå.',
                    style: DriftProTheme.bodySm.copyWith(color: Colors.grey),
                  )
                else
                  ..._history.map((d) {
                    final date =
                        '${d.workDate.year}-${d.workDate.month.toString().padLeft(2, '0')}-${d.workDate.day.toString().padLeft(2, '0')}';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.directions_walk),
                      title: Text(date),
                      trailing: Text(
                        '${d.stepsAtWork} skritt',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    );
                  }),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _deleteData,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Slett mine skrittdata i DriftPro'),
                ),
                const SizedBox(height: 24),
                Text(
                  'Kun for MAVI-ansatte. Ingen tracking. Apple Helse / Google Health Connect '
                  'brukes kun til skritt etter ditt samtykke.',
                  style: DriftProTheme.bodySm.copyWith(
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
    );
  }
}
