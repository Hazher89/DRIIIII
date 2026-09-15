import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/session_sign_out.dart';
import '../../core/services/drive_monitor/drive_monitor_service.dart';
import '../../models/user_profile.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Låst fullskjerm for leiebil-sporing (enhetskonto).
class DriveMonitorKioskScreen extends StatefulWidget {
  const DriveMonitorKioskScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<DriveMonitorKioskScreen> createState() => _DriveMonitorKioskScreenState();
}

class _DriveMonitorKioskScreenState extends State<DriveMonitorKioskScreen> {
  DriveMonitorTracker? _tracker;
  StreamSubscription<DriveMonitorLiveStatus>? _sub;
  DriveMonitorLiveStatus? _live;
  String? _sessionId;
  String? _vehicleLabel;
  bool _starting = false;
  bool _loadingVehicles = true;
  List<Map<String, dynamic>> _vehicles = [];
  int _secretTaps = 0;
  DateTime? _secretWindowStart;
  final _pinCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadVehicles();
  }

  @override
  void dispose() {
    unawaited(_tracker?.stop());
    _sub?.cancel();
    _pinCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadVehicles() async {
    final cid = widget.profile.companyId;
    if (cid == null) {
      setState(() => _loadingVehicles = false);
      return;
    }
    try {
      final list = await DriveMonitorService.listVehicles(cid);
      if (!mounted) return;
      setState(() {
        _vehicles = list;
        _loadingVehicles = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingVehicles = false);
    }
  }

  Future<void> _startForVehicle(Map<String, dynamic> v) async {
    final cid = widget.profile.companyId;
    if (cid == null || _starting) return;
    setState(() => _starting = true);
    try {
      final unit = (v['unit_code'] as String?)?.trim() ?? '';
      final reg = (v['registration_number'] as String?)?.trim() ?? '';
      final label = [
        if (unit.isNotEmpty) unit,
        if (reg.isNotEmpty && reg != '—') reg,
      ].join(' · ');
      final sessionId = await DriveMonitorService.startSession(
        companyId: cid,
        deviceProfileId: widget.profile.id,
        partnerVehicleId: v['id'] as String?,
        vehicleLabel: label.isEmpty ? 'Leiebil' : label,
      );
      final tracker = DriveMonitorTracker(companyId: cid, sessionId: sessionId);
      await tracker.start();
      _sub = tracker.statusStream.listen((s) {
        if (mounted) setState(() => _live = s);
      });
      if (!mounted) return;
      setState(() {
        _tracker = tracker;
        _sessionId = sessionId;
        _vehicleLabel = label.isEmpty ? 'Leiebil' : label;
        _starting = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _starting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke starte sporing: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _onSecretTap() {
    final now = DateTime.now();
    if (_secretWindowStart == null ||
        now.difference(_secretWindowStart!).inSeconds > 3) {
      _secretWindowStart = now;
      _secretTaps = 1;
      return;
    }
    _secretTaps++;
    if (_secretTaps >= 7) {
      _secretTaps = 0;
      _secretWindowStart = null;
      unawaited(_askExitPin());
    }
  }

  Future<void> _askExitPin() async {
    final cid = widget.profile.companyId;
    if (cid == null) return;
    _pinCtrl.clear();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Avslutt sporing'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Skriv inn hemmelig PIN for å låse opp enheten.'),
            const SizedBox(height: 12),
            TextField(
              controller: _pinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'PIN',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bekreft'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final valid = await DriveMonitorService.verifyExitPin(cid, _pinCtrl.text);
    if (!valid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feil PIN'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    await _tracker?.stop();
    if (!mounted) return;
    await signOutFromPortal(context);
  }

  Color get _statusColor {
    switch (_live?.status) {
      case 'rough':
        return const Color(0xFFDC2626);
      case 'warning':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF15803D);
    }
  }

  String get _statusLabel {
    switch (_live?.status) {
      case 'rough':
        return 'RÅ KJØRING';
      case 'warning':
        return 'ADVARSEL';
      default:
        return 'OK';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingVehicles) {
      return const Scaffold(body: DriftProLoadingCenter());
    }

    if (_sessionId == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Leiebil-sporing',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Velg bilen som skal spores. Enheten låses etter start.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), height: 1.35),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: _vehicles.isEmpty
                      ? Center(
                          child: Text(
                            'Ingen aktive biler funnet.',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _vehicles.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final v = _vehicles[i];
                            final unit = v['unit_code'] ?? '';
                            final reg = v['registration_number'] ?? '';
                            return Material(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              child: ListTile(
                                title: Text(
                                  '$unit',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  '$reg',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
                                ),
                                trailing: _starting
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.play_circle_fill, color: Color(0xFF4ADE80)),
                                onTap: _starting ? null : () => _startForVehicle(v),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final speed = _live?.speedKmh ?? 0;
    final score = _live?.score ?? 100;
    final km = _live?.km ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _vehicleLabel ?? 'Leiebil',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _statusColor, width: 2),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _statusLabel,
                          style: TextStyle(
                            color: _statusColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 28,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _live?.online == false
                              ? 'Offline — lagrer lokalt'
                              : 'Sporing aktiv · kontinuerlig',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: _metric('Hastighet', '${speed.toStringAsFixed(0)} km/t')),
                      const SizedBox(width: 10),
                      Expanded(child: _metric('Score', score.toStringAsFixed(0))),
                      const SizedBox(width: 10),
                      Expanded(child: _metric('Km', km.toStringAsFixed(1))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _metric('Hendelser', '${_live?.eventCount ?? 0}'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _metric('Rå', '${_live?.roughCount ?? 0}', alert: true),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    _live?.online == false
                        ? 'Ingen nett — data lagres på telefonen og sendes automatisk når nett er tilbake.'
                        : 'Hold telefonen festet i bilen. Data sendes kontinuerlig til DriftPro (også i bakgrunn).',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onSecretTap,
              child: const SizedBox(width: 72, height: 72),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, {bool alert = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: alert ? const Color(0xFFF87171) : Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
