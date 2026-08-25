import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/services/partner/partner_workforce_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_workforce.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import '../widgets/partner_portal_page_shell.dart';
import '../widgets/partner_ui.dart';

/// Stempling for partner-ansatte — status, live-tid og arkiv.
class StaffPortalPunchPage extends StatefulWidget {
  final Partner partner;
  final UserProfile profile;

  const StaffPortalPunchPage({
    super.key,
    required this.partner,
    required this.profile,
  });

  @override
  State<StaffPortalPunchPage> createState() => _StaffPortalPunchPageState();
}

class _StaffPortalPunchPageState extends State<StaffPortalPunchPage> {
  List<PartnerTimeEntry> _mine = [];
  PartnerTimeEntry? _open;
  bool _loading = true;
  bool _busy = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _ensureTick() {
    _tick?.cancel();
    if (_open == null) return;
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = await PartnerWorkforceService.myStaffRecord();
      final entries = await PartnerWorkforceService.listEntries(
        partnerId: widget.partner.id,
        staffId: me?.id,
        from: DateTime.now().subtract(const Duration(days: 30)),
      );
      final open = entries.where((e) => e.isOpen).firstOrNull;
      if (!mounted) return;
      setState(() {
        _mine = entries;
        _open = open;
        _loading = false;
      });
      _ensureTick();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _punch() async {
    setState(() => _busy = true);
    try {
      final res = await PartnerWorkforceService.punch();
      if (!mounted) return;
      final action = res['action']?.toString() ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(action == 'punch_in' ? 'Stemplet inn' : 'Stemplet ut'),
          backgroundColor: action == 'punch_in'
              ? DriftProTheme.primaryGreen
              : Colors.blueGrey,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: DriftProTheme.error),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  double get _periodHours {
    var minutes = 0;
    for (final e in _mine) {
      if (e.isOpen) {
        minutes += DateTime.now().difference(e.clockIn).inMinutes;
      } else if (e.duration != null) {
        minutes += e.duration!.inMinutes;
      }
    }
    return minutes / 60.0;
  }

  Map<String, List<PartnerTimeEntry>> get _byDay {
    final map = <String, List<PartnerTimeEntry>>{};
    final keyFmt = DateFormat('yyyy-MM-dd');
    for (final e in _mine) {
      final k = keyFmt.format(e.clockIn.toLocal());
      map.putIfAbsent(k, () => []).add(e);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final muted = PartnerUi.mutedText(context);
    final clockedIn = _open != null;
    final elapsed = clockedIn
        ? DateTime.now().difference(_open!.clockIn)
        : Duration.zero;
    final dayFmt = DateFormat('EEEE d. MMM', 'nb');
    final timeFmt = DateFormat('HH:mm');

    return PartnerPortalPageShell(
      title: 'Stempling',
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        IconButton(
          tooltip: 'Logg ut',
          icon: const Icon(Icons.logout),
          onPressed: () => signOutFromPortal(context),
        ),
      ],
      body: _loading
          ? const DriftProLoadingCenter()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    widget.partner.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _StatusHero(
                    clockedIn: clockedIn,
                    elapsed: elapsed,
                    clockInAt: _open?.clockIn,
                    periodHours: _periodHours,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 56,
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _punch,
                      style: FilledButton.styleFrom(
                        backgroundColor: clockedIn
                            ? const Color(0xFFC62828)
                            : DriftProTheme.primaryGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: Icon(
                        clockedIn ? Icons.logout_rounded : Icons.login_rounded,
                      ),
                      label: Text(
                        clockedIn ? 'Stemple ut' : 'Stemple inn',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Text(
                        'Arkiv',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: muted.withValues(alpha: 0.95),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Siste 30 dager',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_mine.isEmpty)
                    _EmptyArchive(muted: muted)
                  else
                    ..._byDay.entries.map((day) {
                      final date = DateTime.parse(day.key);
                      final dayMinutes = day.value.fold<int>(0, (sum, e) {
                        if (e.isOpen) {
                          return sum +
                              DateTime.now().difference(e.clockIn).inMinutes;
                        }
                        return sum + (e.duration?.inMinutes ?? 0);
                      });
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _DayGroup(
                          title: dayFmt.format(date),
                          hoursLabel: PartnerWorkforceService.formatHours(
                            Duration(minutes: dayMinutes),
                          ),
                          children: day.value.map((e) {
                            return _EntryTile(
                              clockIn: timeFmt.format(e.clockIn.toLocal()),
                              clockOut: e.isOpen
                                  ? 'Pågår'
                                  : timeFmt.format(e.clockOut!.toLocal()),
                              hours: e.isOpen
                                  ? PartnerWorkforceService.formatDurationClock(
                                      DateTime.now().difference(e.clockIn),
                                    )
                                  : PartnerWorkforceService.formatHours(
                                      e.duration,
                                    ),
                              isOpen: e.isOpen,
                              note: e.note,
                            );
                          }).toList(),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({
    required this.clockedIn,
    required this.elapsed,
    required this.clockInAt,
    required this.periodHours,
  });

  final bool clockedIn;
  final Duration elapsed;
  final DateTime? clockInAt;
  final double periodHours;

  @override
  Widget build(BuildContext context) {
    final accent = clockedIn ? DriftProTheme.primaryGreen : Colors.blueGrey;
    final timeFmt = DateFormat('HH:mm');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.16),
            accent.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  clockedIn ? 'STEMPELT INN' : 'STEMPELT UT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: accent,
                  ),
                ),
              ),
              const Spacer(),
              Icon(
                clockedIn ? Icons.timelapse_rounded : Icons.schedule_rounded,
                color: accent,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            clockedIn
                ? PartnerWorkforceService.formatDurationClock(elapsed)
                : 'Klar til å stemple',
            style: TextStyle(
              fontSize: clockedIn ? 36 : 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: accent,
            ),
          ),
          if (clockedIn && clockInAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Inn kl. ${timeFmt.format(clockInAt!.toLocal())}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: PartnerUi.mutedText(context),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              _MiniStat(
                label: 'Periode',
                value: '${periodHours.toStringAsFixed(1)} t',
              ),
              const SizedBox(width: 10),
              _MiniStat(
                label: 'Status',
                value: clockedIn ? 'På jobb' : 'Ferdig',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: PartnerUi.mutedText(context),
              ),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyArchive extends StatelessWidget {
  const _EmptyArchive({required this.muted});
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 36, color: muted),
          const SizedBox(height: 8),
          Text(
            'Ingen stemplinger ennå',
            style: TextStyle(fontWeight: FontWeight.w700, color: muted),
          ),
          const SizedBox(height: 4),
          Text(
            'Når du stempler inn, vises historikken her.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: muted),
          ),
        ],
      ),
    );
  }
}

class _DayGroup extends StatelessWidget {
  const _DayGroup({
    required this.title,
    required this.hoursLabel,
    required this.children,
  });

  final String title;
  final String hoursLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final muted = PartnerUi.mutedText(context);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  hoursLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: muted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.clockIn,
    required this.clockOut,
    required this.hours,
    required this.isOpen,
    this.note,
  });

  final String clockIn;
  final String clockOut;
  final String hours;
  final bool isOpen;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final muted = PartnerUi.mutedText(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOpen ? DriftProTheme.primaryGreen : Colors.blueGrey.shade300,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$clockIn  →  $clockOut',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (note != null && note!.trim().isNotEmpty)
                  Text(note!, style: TextStyle(fontSize: 12, color: muted)),
              ],
            ),
          ),
          Text(
            hours,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: isOpen ? DriftProTheme.primaryGreen : muted,
            ),
          ),
        ],
      ),
    );
  }
}
