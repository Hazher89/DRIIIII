import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/driftpro_brand.dart';
import '../../../core/services/time_clock/time_clock_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/time_clock/time_work_type.dart';
import '../../../widgets/driftpro_brand_logo.dart';
import '../widgets/live_clock.dart';

enum _KioskStep { login, punch, success }

/// Fullskjerm kiosk for stempling — offentlig URL /stemple (som driftpro.no/stemple).
class KioskScreen extends StatefulWidget {
  const KioskScreen({super.key, required this.slug});

  final String slug;

  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> {
  final _employeeCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _employeeFocus = FocusNode();
  final _pinFocus = FocusNode();

  _KioskStep _step = _KioskStep.login;
  bool _darkMode = false;
  bool _loading = false;
  String? _error;

  String? _sessionToken;
  String? _fullName;
  bool _isClockedIn = false;
  DateTime? _clockedInAt;
  int _resetSeconds = 4;
  String? _selectedWorkTypeId;
  List<TimeWorkType> _workTypes = [];
  String? _companyName;
  Timer? _resetTimer;
  Timer? _durationTimer;

  static const _bgLight = Color(0xFFF3F6F4);
  static const _bgDark = Color(0xFF121816);

  @override
  void initState() {
    super.initState();
    _loadCompany();
    _durationTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _isClockedIn) setState(() {});
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _durationTimer?.cancel();
    _employeeCtrl.dispose();
    _pinCtrl.dispose();
    _employeeFocus.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _loadCompany() async {
    setState(() => _loading = true);
    try {
      final res = await TimeClockService.kioskGetCompany(widget.slug);
      if (res['ok'] != true) {
        setState(() {
          _error = res['error'] as String? ?? 'Kiosk ikke funnet';
          _loading = false;
        });
        return;
      }
      setState(() {
        _companyName = res['display_name'] as String?;
        _resetSeconds = res['punch_reset_seconds'] as int? ?? 4;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Kunne ikke laste kiosk';
        _loading = false;
      });
    }
  }

  String get _effectivePin {
    final pin = _pinCtrl.text.trim();
    return pin.isEmpty ? '0' : pin;
  }

  Future<void> _login() async {
    final employeeNumber = _employeeCtrl.text.trim();
    if (employeeNumber.isEmpty) {
      setState(() => _error = 'Fyll inn ansattnummer');
      _employeeFocus.requestFocus();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await TimeClockService.kioskLogin(
        slug: widget.slug,
        employeeNumber: employeeNumber,
        pin: _effectivePin,
      );
      if (res['ok'] != true) {
        setState(() {
          _error = res['error'] as String? ?? 'Innlogging feilet';
          _loading = false;
        });
        return;
      }
      _sessionToken = res['session_token'] as String?;
      _fullName = res['full_name'] as String?;
      _isClockedIn = res['is_clocked_in'] as bool? ?? false;
      _selectedWorkTypeId = res['default_work_type_id'] as String?;
      _resetSeconds = res['punch_reset_seconds'] as int? ?? _resetSeconds;
      final inAt = res['clocked_in_at'] as String?;
      _clockedInAt = inAt != null ? DateTime.tryParse(inAt) : null;

      if (_sessionToken != null) {
        _workTypes = await TimeClockService.kioskFetchWorkTypes(_sessionToken!);
        if (_selectedWorkTypeId == null && _workTypes.isNotEmpty) {
          _selectedWorkTypeId = _workTypes.firstWhere(
            (t) => t.isDefaultPunch,
            orElse: () => _workTypes.first,
          ).id;
        }
      }

      setState(() {
        _step = _KioskStep.punch;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Innlogging feilet';
        _loading = false;
      });
    }
  }

  Future<void> _punch() async {
    if (_sessionToken == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await TimeClockService.kioskPunch(
        sessionToken: _sessionToken!,
        workTypeId: _selectedWorkTypeId,
      );
      if (res['ok'] != true) {
        setState(() {
          _error = res['error'] as String? ?? 'Stempling feilet';
          _loading = false;
        });
        return;
      }
      final punchType = res['punch_type'] as String?;
      setState(() {
        _isClockedIn = punchType == 'in';
        if (punchType == 'in') {
          _clockedInAt = DateTime.tryParse(res['punched_at'] as String? ?? '') ?? DateTime.now();
        } else {
          _clockedInAt = null;
        }
        _step = _KioskStep.success;
        _loading = false;
      });
      _scheduleReset();
    } catch (e) {
      setState(() {
        _error = 'Stempling feilet';
        _loading = false;
      });
    }
  }

  void _scheduleReset() {
    _resetTimer?.cancel();
    _resetTimer = Timer(Duration(seconds: _resetSeconds), _backToLogin);
  }

  void _backToLogin() {
    if (!mounted) return;
    _resetTimer?.cancel();
    _employeeCtrl.clear();
    _pinCtrl.clear();
    setState(() {
      _step = _KioskStep.login;
      _sessionToken = null;
      _fullName = null;
      _isClockedIn = false;
      _clockedInAt = null;
      _error = null;
      _workTypes = [];
      _selectedWorkTypeId = null;
    });
  }

  String _durationLabel() {
    if (!_isClockedIn || _clockedInAt == null) return '00t 00m';
    final diff = DateTime.now().difference(_clockedInAt!);
    return '${diff.inHours.toString().padLeft(2, '0')}t ${diff.inMinutes.remainder(60).toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    final bg = _darkMode ? _bgDark : _bgLight;
    final fg = _darkMode ? Colors.white : const Color(0xFF1A2E22);
    final cardBg = _darkMode ? const Color(0xFF1E2A24) : Colors.white;

    if (_error != null && _companyName == null && !_loading) {
      return Scaffold(
        backgroundColor: bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: fg)),
              TextButton(onPressed: () => context.go('/login'), child: const Text('Til app')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _topBar(fg, cardBg),
                Expanded(
                  child: _step == _KioskStep.login
                      ? _buildLogin(fg, cardBg)
                      : _buildPunch(fg, cardBg),
                ),
              ],
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: IconButton.filledTonal(
                tooltip: _darkMode ? 'Lys modus' : 'Nattmodus',
                onPressed: () => setState(() => _darkMode = !_darkMode),
                icon: Icon(_darkMode ? Icons.wb_sunny_outlined : Icons.nightlight_round),
              ),
            ),
            if (_loading)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x44000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(Color fg, Color cardBg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border(bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          const DriftProBrandLogo(density: DriftProBrandDensity.compact, showSubtitle: false),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule, size: 18, color: fg.withValues(alpha: 0.6)),
                  const SizedBox(width: 6),
                  Text(
                    'Stempling',
                    style: TextStyle(fontWeight: FontWeight.w700, color: fg, fontSize: 15),
                  ),
                ],
              ),
              LiveClock(
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w300, color: fg),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogin(Color fg, Color cardBg) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            elevation: 0,
            color: cardBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Logg på ${_companyName ?? 'bedriften'}',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: fg),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Skriv ansattnummer og PIN-kode. Standard PIN er 0.',
                    style: TextStyle(fontSize: 15, color: fg.withValues(alpha: 0.65), height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _employeeCtrl,
                    focusNode: _employeeFocus,
                    decoration: const InputDecoration(
                      labelText: 'Ansattnummer',
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => _pinFocus.requestFocus(),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pinCtrl,
                    focusNode: _pinFocus,
                    decoration: const InputDecoration(
                      labelText: 'PIN-kode',
                      hintText: '0',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => _login(),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, style: const TextStyle(color: DriftProTheme.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _login,
                    style: FilledButton.styleFrom(
                      backgroundColor: DriftProTheme.primaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Logg inn'),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    DriftProBrand.subtitle,
                    style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.45)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPunch(Color fg, Color cardBg) {
    if (_step == _KioskStep.success) {
      return Center(
        child: Card(
          elevation: 0,
          color: cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isClockedIn ? Icons.login_rounded : Icons.logout_rounded,
                  size: 72,
                  color: _isClockedIn ? DriftProTheme.success : DriftProTheme.warning,
                ),
                const SizedBox(height: 16),
                Text(
                  _isClockedIn ? 'Innstemplet!' : 'Utstemplet!',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: fg),
                ),
                const SizedBox(height: 8),
                Text(_fullName ?? '', style: TextStyle(fontSize: 18, color: fg.withValues(alpha: 0.7))),
                const SizedBox(height: 24),
                Text(
                  'Tilbake om $_resetSeconds sek…',
                  style: TextStyle(color: fg.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final selectedType = _workTypes.cast<TimeWorkType?>().firstWhere(
          (t) => t?.id == _selectedWorkTypeId,
          orElse: () => _workTypes.isNotEmpty ? _workTypes.first : null,
        );

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > 900;
        final left = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Hei, ${_fullName ?? ''}',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: fg),
                  ),
                ),
                Text(_durationLabel(), style: TextStyle(fontSize: 18, color: fg.withValues(alpha: 0.6))),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              DateFormat('EEEE d. MMMM', 'nb').format(DateTime.now()),
              style: TextStyle(color: fg.withValues(alpha: 0.55)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: DriftProTheme.error)),
            ],
            const SizedBox(height: 20),
            Card(
              elevation: 0,
              color: cardBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isClockedIn ? 'Du er innstemplet' : 'Klar til innstempling',
                      style: TextStyle(color: fg.withValues(alpha: 0.55)),
                    ),
                    if (_isClockedIn && _clockedInAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Siden ${DateFormat('HH:mm').format(_clockedInAt!.toLocal())}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 64,
                      child: FilledButton.icon(
                        onPressed: _punch,
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              _isClockedIn ? DriftProTheme.warning : DriftProTheme.primaryGreen,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: Icon(_isClockedIn ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 28),
                        label: Text(
                          _isClockedIn ? 'Stemple ut' : 'Stemple inn',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_workTypes.length > 1) ...[
              const SizedBox(height: 16),
              Text('Arbeidstype', style: TextStyle(fontWeight: FontWeight.w600, color: fg)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _workTypes.map((wt) {
                  final selected = wt.id == _selectedWorkTypeId;
                  return ChoiceChip(
                    label: Text(wt.label),
                    selected: selected,
                    onSelected: _isClockedIn
                        ? null
                        : (v) {
                            if (v) setState(() => _selectedWorkTypeId = wt.id);
                          },
                    selectedColor: wt.color.withValues(alpha: 0.25),
                    side: BorderSide(color: selected ? wt.color : Colors.grey.shade300),
                  );
                }).toList(),
              ),
            ] else if (selectedType != null) ...[
              const SizedBox(height: 12),
              Text('Vakt: ${selectedType.name}', style: TextStyle(color: fg.withValues(alpha: 0.6))),
            ],
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: _backToLogin, child: const Text('Logg ut')),
            ),
          ],
        );

        final right = Card(
          elevation: 0,
          color: cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Timeliste i dag', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Divider(),
                Expanded(
                  child: Center(
                    child: Text(
                      _isClockedIn && _clockedInAt != null
                          ? 'Stemplet inn kl. ${DateFormat('HH:mm').format(_clockedInAt!.toLocal())}'
                          : 'Ingen registrering i dag ennå',
                      style: TextStyle(color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        return Padding(
          padding: const EdgeInsets.all(20),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: left),
                    const SizedBox(width: 20),
                    Expanded(flex: 4, child: right),
                  ],
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      left,
                      const SizedBox(height: 16),
                      SizedBox(height: 200, child: right),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
