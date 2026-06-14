import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/services/time_clock/time_clock_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/time_clock/time_work_type.dart';
import '../../../models/user_profile.dart';
import '../widgets/live_clock.dart';

class TimeClockMobileTab extends StatefulWidget {
  const TimeClockMobileTab({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<TimeClockMobileTab> createState() => _TimeClockMobileTabState();
}

class _TimeClockMobileTabState extends State<TimeClockMobileTab> {
  bool _mobileAllowed = false;
  bool _isClockedIn = false;
  DateTime? _clockedInAt;
  List<TimeWorkType> _workTypes = [];
  String? _defaultWorkTypeId;
  bool _loading = true;
  bool _punching = false;
  String? _error;
  Timer? _durationTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _durationTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _isClockedIn) setState(() {});
    });
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final allowed = await TimeClockService.hasMobileAccess();
      final state = await TimeClockService.fetchMyClockState();
      final companyId = widget.profile.companyId;
      List<TimeWorkType> types = [];
      if (companyId != null) {
        types = await TimeClockService.fetchWorkTypes(companyId);
      }
      if (!mounted) return;
      setState(() {
        _mobileAllowed = allowed;
        _isClockedIn = state?['is_clocked_in'] as bool? ?? false;
        final inAt = state?['clocked_in_at'] as String?;
        _clockedInAt = inAt != null ? DateTime.tryParse(inAt) : null;
        _workTypes = types;
        _defaultWorkTypeId = state?['work_type_id'] as String? ??
            types.where((t) => t.isDefaultPunch).map((t) => t.id).firstOrNull;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Kunne ikke laste status';
        _loading = false;
      });
    }
  }

  String _durationLabel() {
    if (!_isClockedIn || _clockedInAt == null) return '00t 00m';
    final diff = DateTime.now().difference(_clockedInAt!);
    return '${diff.inHours.toString().padLeft(2, '0')}t ${diff.inMinutes.remainder(60).toString().padLeft(2, '0')}m';
  }

  Future<void> _punch() async {
    setState(() => _punching = true);
    HapticFeedback.mediumImpact();
    try {
      final res = await TimeClockService.punchMobile(workTypeId: _defaultWorkTypeId);
      if (res['ok'] != true) {
        setState(() => _error = res['error'] as String? ?? 'Stempling feilet');
        return;
      }
      final punchType = res['punch_type'] as String?;
      final overtimeHours = (res['overtime_hours'] as num?)?.toDouble() ?? 0;
      if (punchType == 'out' && overtimeHours > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Overtid registrert: ${overtimeHours.toStringAsFixed(1)} t '
              '(40 % tillegg etter §10-6)',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      await _load();
    } catch (e) {
      setState(() => _error = 'Stempling feilet');
    } finally {
      if (mounted) setState(() => _punching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_mobileAllowed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.phonelink_lock, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'Mobilstempling er ikke aktivert for deg',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Du må stemple inn via kiosk-terminalen på jobb. '
                'Kontakt leder hvis du trenger mobiltilgang.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    final defaultType = _workTypes.cast<TimeWorkType?>().firstWhere(
          (t) => t?.id == _defaultWorkTypeId,
          orElse: () => _workTypes.isNotEmpty ? _workTypes.first : null,
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              LiveClock(showDate: true),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('I dag', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                      Text(_durationLabel(), style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    defaultType?.name ?? 'Ingen vakt i dag',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isClockedIn ? 'Innstemplet' : 'Ikke innstemplet',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _punching ? null : _punch,
                      style: FilledButton.styleFrom(
                        backgroundColor: _isClockedIn ? Colors.orange.shade700 : DriftProTheme.success,
                      ),
                      icon: _punching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(_isClockedIn ? Icons.stop_rounded : Icons.play_arrow_rounded),
                      label: Text(_isClockedIn ? 'Stemple ut' : 'Stemple inn'),
                    ),
                  ),
                  if (_isClockedIn && _clockedInAt != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Inn ${DateFormat('HH:mm').format(_clockedInAt!.toLocal())}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: DriftProTheme.error)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
