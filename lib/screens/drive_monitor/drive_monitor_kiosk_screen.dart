import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/session_sign_out.dart';
import '../../core/services/drive_monitor/drive_monitor_service.dart';
import '../../models/user_profile.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Låst fullskjerm for sporingsenhet — ikke knyttet til MAVI-biler.
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
  String? _unitLabel;
  bool _starting = true;
  int _secretTaps = 0;
  DateTime? _secretWindowStart;
  final _pinCtrl = TextEditingController();

  String get _defaultUnitName {
    final named = widget.profile.driveMonitorUnitName?.trim();
    if (named != null && named.isNotEmpty) return named;
    return widget.profile.fullName;
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    unawaited(_autoStart());
  }

  @override
  void dispose() {
    unawaited(_tracker?.stop());
    _sub?.cancel();
    _pinCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _autoStart() async {
    final cid = widget.profile.companyId;
    if (cid == null) {
      if (mounted) setState(() => _starting = false);
      return;
    }
    try {
      final label = _defaultUnitName;
      final sessionId = await DriveMonitorService.startSession(
        companyId: cid,
        deviceProfileId: widget.profile.id,
        vehicleLabel: label,
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
        _unitLabel = label;
        _starting = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _starting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunne ikke starte sporing: $e'),
            backgroundColor: Colors.red,
          ),
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
    if (_starting || _sessionId == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DriftProLoadingCenter(),
              const SizedBox(height: 16),
              Text(
                _starting
                    ? 'Starter sporing for $_defaultUnitName…'
                    : 'Venter på GPS…',
                style: const TextStyle(color: Colors.white70),
              ),
              if (!_starting) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() => _starting = true);
                    unawaited(_autoStart());
                  },
                  child: const Text('Prøv igjen'),
                ),
              ],
            ],
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
                    _unitLabel ?? _defaultUnitName,
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
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${speed.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 72,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                        Text(
                          'km/t',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _kpi('Km', km.toStringAsFixed(1)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _kpi('Score', score.toStringAsFixed(0)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _statusColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _statusColor),
                          ),
                          child: Text(
                            _statusLabel,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _statusColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    _live?.online == false
                        ? 'Offline — rute lagres lokalt og synces når nett er tilbake'
                        : 'GPS-rute lagres fortløpende · bakgrunnssporet aktivt',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              onTap: _onSecretTap,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox(width: 72, height: 72),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
