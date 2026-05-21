import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/company_display.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/tidsbanken/tidsbanken_presence_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/norwegian_national_id.dart';
import '../../models/absence.dart';
import '../../models/tidsbanken_presence.dart';
import '../../models/user_profile.dart';

/// Infoskjerm: én side uten scrolling — 6 paneler (på jobb, ferie, bursdag).
class OnlinePresenceScreen extends StatefulWidget {
  final bool embedded;

  const OnlinePresenceScreen({super.key, this.embedded = false});

  @override
  State<OnlinePresenceScreen> createState() => _OnlinePresenceScreenState();
}

class _BirthdayEntry {
  final UserProfile profile;
  final DateTime birthday;
  final int daysUntil;
  final int ageNext;

  _BirthdayEntry({
    required this.profile,
    required this.birthday,
    required this.daysUntil,
    required this.ageNext,
  });
}

class _OnlinePresenceScreenState extends State<OnlinePresenceScreen> {
  static const _refreshInterval = Duration(minutes: 5);
  static const int _maxLines = 9;

  Timer? _timer;
  bool _loading = true;
  bool _syncing = false;
  String? _error;
  String _companyTitle = CompanyDisplay.defaultName;
  List<TidsbankenPresence> _presence = [];
  TidsbankenSyncState? _sync;
  List<Absence> _absences = [];
  List<UserProfile> _profiles = [];

  @override
  void initState() {
    super.initState();
    _load(trySync: true);
    _timer = Timer.periodic(_refreshInterval, (_) => _load(trySync: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isApprovedVacationActiveToday(Absence a) {
    if (a.type != AbsenceType.ferie || a.status != AbsenceStatus.godkjent) return false;
    final today = _dayOnly(DateTime.now());
    final start = _dayOnly(a.startDate);
    final end = _dayOnly(a.endDate);
    return !end.isBefore(today) && !start.isAfter(today);
  }

  Future<void> _load({bool trySync = false}) async {
    if (!mounted) return;
    setState(() {
      if (_presence.isEmpty) _loading = true;
      _syncing = trySync;
      _error = null;
    });

    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId == null) {
        setState(() {
          _loading = false;
          _syncing = false;
          _error = 'Fant ingen bedrift.';
        });
        return;
      }

      final meta = await SupabaseService.fetchCompanyDashboardMeta(companyId);
      final tidsOn = await TidsbankenPresenceService.isEnabledForCompany(companyId);

      if (trySync && tidsOn) {
        final syncRes = await TidsbankenPresenceService.syncNow();
        if (!syncRes.ok && syncRes.error != null) _error = syncRes.error;
      }

      final bundle = await TidsbankenPresenceService.loadForCurrentCompany(trySync: false);
      final absences = await SupabaseService.fetchAbsences(companyId: companyId);
      final profiles = await SupabaseService.fetchProfiles(companyId: companyId);

      if (!mounted) return;
      setState(() {
        _companyTitle = CompanyDisplay.resolve(meta.companyName);
        _presence = bundle.rows;
        _sync = bundle.sync;
        _absences = absences;
        _profiles = profiles.where((p) => p.isActive).toList();
        _loading = false;
        _syncing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _syncing = false;
        _error = e.toString();
      });
    }
  }

  List<TidsbankenPresence> get _clockedIn =>
      _presence.where((p) => p.isClockedIn).toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName));

  List<TidsbankenPresence> get _notIn =>
      _presence.where((p) => !p.isClockedIn).toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName));

  List<Absence> get _vacationNow => _absences
      .where(_isApprovedVacationActiveToday)
      .toList()
    ..sort((a, b) => (a.userName ?? '').compareTo(b.userName ?? ''));

  List<Absence> get _vacationSoon {
    final today = _dayOnly(DateTime.now());
    final horizon = today.add(const Duration(days: 90));
    return _absences
        .where((a) {
          if (a.type != AbsenceType.ferie || a.status != AbsenceStatus.godkjent) {
            return false;
          }
          final start = _dayOnly(a.startDate);
          return start.isAfter(today) && !start.isAfter(horizon);
        })
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  List<_BirthdayEntry> get _birthdaysToday {
    final out = <_BirthdayEntry>[];
    for (final p in _profiles) {
      final bday = p.birthDate ?? NorwegianNationalId.birthDateFrom(p.nationalIdNumber);
      if (bday == null) continue;
      if (NorwegianNationalId.daysUntilNextBirthday(bday) != 0) continue;
      out.add(_BirthdayEntry(
        profile: p,
        birthday: bday,
        daysUntil: 0,
        ageNext: NorwegianNationalId.ageOnNextBirthday(bday),
      ));
    }
    out.sort((a, b) => a.profile.fullName.compareTo(b.profile.fullName));
    return out;
  }

  List<_BirthdayEntry> get _birthdaysSoon {
    final out = <_BirthdayEntry>[];
    for (final p in _profiles) {
      final bday = p.birthDate ?? NorwegianNationalId.birthDateFrom(p.nationalIdNumber);
      if (bday == null) continue;
      final days = NorwegianNationalId.daysUntilNextBirthday(bday);
      if (days <= 0 || days > 30) continue;
      out.add(_BirthdayEntry(
        profile: p,
        birthday: bday,
        daysUntil: days,
        ageNext: NorwegianNationalId.ageOnNextBirthday(bday),
      ));
    }
    out.sort((a, b) => a.daysUntil.compareTo(b.daysUntil));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F1419) : const Color(0xFFF4F6F8);

    final body = ColoredBox(
      color: bg,
      child: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: DriftProTheme.primaryGreen))
            : LayoutBuilder(
                builder: (context, constraints) {
                  return Column(
                    children: [
                      _topBar(isDark),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: _errorStrip(_error!),
                        ),
                      Expanded(child: _gridBoard(isDark, constraints)),
                    ],
                  );
                },
              ),
      ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: bg,
      body: body,
    );
  }

  Widget _topBar(bool isDark) {
    final sync = _sync;
    final timeFmt = DateFormat('HH:mm', 'nb');
    final dateFmt = DateFormat('EEEE d. MMMM', 'nb');
    final now = DateTime.now();
    final onJob = sync != null && sync.totalCount > 0
        ? '${sync.clockedInCount} / ${sync.totalCount} innstemplt'
        : '${_clockedIn.length} på jobb';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: DriftProTheme.primaryGradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: DriftProTheme.primaryGreen.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.apartment_rounded, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _companyTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  onJob,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_syncing)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white70,
                        ),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: 'Oppdater',
                      onPressed: () => _load(trySync: true),
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  Text(
                    timeFmt.format(now),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              Text(
                dateFmt.format(now),
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
              if (sync?.lastSyncAt != null)
                Text(
                  'Tidsbanken ${timeFmt.format(sync!.lastSyncAt!.toLocal())}',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _errorStrip(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
    );
  }

  Widget _gridBoard(bool isDark, BoxConstraints constraints) {
    final pad = 12.0;
    final gap = 10.0;
    final cols = constraints.maxWidth >= 900 ? 3 : 2;
    final rows = cols == 3 ? 2 : 3;

    final tiles = <_PanelData>[
      _PanelData(
        title: 'På jobb nå',
        icon: Icons.login_rounded,
        accent: const Color(0xFF2E7D32),
        count: _clockedIn.length,
        lines: _clockedIn
            .map((p) => _LineItem(
                  title: p.fullName,
                  subtitle: p.sinceTime != null ? 'Siden ${p.sinceTime}' : 'Innstemplt',
                ))
            .toList(),
        empty: 'Ingen innstemplt',
      ),
      _PanelData(
        title: 'Ikke innstemplt',
        icon: Icons.logout_rounded,
        accent: Colors.grey.shade600,
        count: _notIn.length,
        lines: _notIn
            .map((p) => _LineItem(title: p.fullName, subtitle: 'Ikke inne'))
            .toList(),
        empty: 'Alle er innstemplt',
      ),
      _PanelData(
        title: 'Ferie nå',
        icon: Icons.beach_access_rounded,
        accent: DriftProTheme.absenceVacation,
        count: _vacationNow.length,
        lines: _vacationLines(_vacationNow, soon: false),
        empty: 'Ingen på ferie i dag',
      ),
      _PanelData(
        title: 'Ferie snart',
        icon: Icons.flight_takeoff_rounded,
        accent: const Color(0xFF1565C0),
        count: _vacationSoon.length,
        lines: _vacationLines(_vacationSoon, soon: true),
        empty: 'Ingen planlagt ferie (90 d)',
      ),
      _PanelData(
        title: 'Bursdag i dag',
        icon: Icons.cake_rounded,
        accent: const Color(0xFFC2185B),
        count: _birthdaysToday.length,
        lines: _birthdayLines(_birthdaysToday, today: true),
        empty: 'Ingen bursdag i dag',
      ),
      _PanelData(
        title: 'Bursdag snart',
        icon: Icons.cake_outlined,
        accent: const Color(0xFFAD1457),
        count: _birthdaysSoon.length,
        lines: _birthdayLines(_birthdaysSoon, today: false),
        empty: 'Ingen innen 30 dager',
      ),
    ];

    return Padding(
      padding: EdgeInsets.all(pad),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: gap,
          mainAxisSpacing: gap,
          childAspectRatio: _aspectRatio(constraints, cols, rows, pad, gap),
        ),
        itemCount: tiles.length,
        itemBuilder: (_, i) => _panelCard(isDark, tiles[i]),
      ),
    );
  }

  double _aspectRatio(BoxConstraints c, int cols, int rows, double pad, double gap) {
    final w = c.maxWidth - pad * 2 - gap * (cols - 1);
    final h = c.maxHeight - 88 - pad * 2 - gap * (rows - 1);
    final cellW = w / cols;
    final cellH = h / rows;
    if (cellH <= 0) return 1.1;
    return cellW / cellH;
  }

  List<_LineItem> _vacationLines(List<Absence> items, {required bool soon}) {
    final fmt = DateFormat('d. MMM', 'nb');
    final today = _dayOnly(DateTime.now());
    return items.map((a) {
      final name = a.userName ?? 'Ansatt';
      final start = _dayOnly(a.startDate);
      String sub;
      if (soon) {
        final d = start.difference(today).inDays;
        sub = d <= 1 ? 'I morgen' : 'Om $d d · fra ${fmt.format(a.startDate)}';
      } else {
        final left = _dayOnly(a.endDate).difference(today).inDays + 1;
        sub = left <= 1 ? 'Siste feriedag' : '$left d igjen';
      }
      return _LineItem(title: name, subtitle: sub);
    }).toList();
  }

  List<_LineItem> _birthdayLines(List<_BirthdayEntry> entries, {required bool today}) {
    return entries.map((e) {
      final label = today
          ? 'Fyller ${e.ageNext} år 🎂'
          : e.daysUntil == 1
              ? 'I morgen · ${e.ageNext} år'
              : 'Om ${e.daysUntil} d · ${e.ageNext} år';
      return _LineItem(title: e.profile.fullName, subtitle: label);
    }).toList();
  }

  Widget _panelCard(bool isDark, _PanelData data) {
    final lines = data.lines;
    final show = lines.take(_maxLines).toList();
    final extra = lines.length - show.length;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: data.accent.withValues(alpha: isDark ? 0.35 : 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: data.accent.withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Icon(data.icon, color: data.accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    data.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: isDark ? Colors.white : Colors.grey[900],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: data.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${data.count}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: show.isEmpty
                ? Center(
                    child: Text(
                      data.empty,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.grey[500],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: show.length + (extra > 0 ? 1 : 0),
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                    ),
                    itemBuilder: (_, i) {
                      if (extra > 0 && i == show.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            '+ $extra til',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: data.accent,
                            ),
                          ),
                        );
                      }
                      final line = show[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: isDark ? Colors.white : Colors.grey[900],
                              ),
                            ),
                            if (line.subtitle != null)
                              Text(
                                line.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDark ? Colors.white54 : Colors.grey[600],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PanelData {
  final String title;
  final IconData icon;
  final Color accent;
  final int count;
  final List<_LineItem> lines;
  final String empty;

  _PanelData({
    required this.title,
    required this.icon,
    required this.accent,
    required this.count,
    required this.lines,
    required this.empty,
  });
}

class _LineItem {
  final String title;
  final String? subtitle;

  _LineItem({required this.title, this.subtitle});
}
