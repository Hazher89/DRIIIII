import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/company_display.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/tidsbanken/tidsbanken_presence_service.dart';
import '../../core/services/wallboard/entur_departures_service.dart';
import '../../core/services/wallboard/nrk_news_feed_service.dart';
import '../../core/services/wallboard/open_meteo_weather_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/wallboard_palette.dart';
import '../../core/utils/norwegian_national_id.dart';
import '../../models/absence.dart';
import '../../models/tidsbanken_presence.dart';
import '../../models/user_profile.dart';
import 'widgets/wallboard_adaptive_people_grid.dart';
import 'widgets/wallboard_extras_bar.dart';
import 'widgets/wallboard_news_ticker.dart';

/// Infoskjerm /live: vær, kollektiv, NRK-ticker + teamoversikt (uten «ikke innstemplt»).
class OnlinePresenceScreen extends StatefulWidget {
  final bool embedded;
  final Duration? refreshInterval;

  const OnlinePresenceScreen({
    super.key,
    this.embedded = false,
    this.refreshInterval,
  });

  @override
  State<OnlinePresenceScreen> createState() => _OnlinePresenceScreenState();
}

class _BirthdayEntry {
  final UserProfile profile;
  final DateTime birthday;
  final int daysUntil;

  _BirthdayEntry({
    required this.profile,
    required this.birthday,
    required this.daysUntil,
  });
}

class _OnlinePresenceScreenState extends State<OnlinePresenceScreen> {
  static const Color _bg = WallboardPalette.background;
  static const Color _card = WallboardPalette.card;

  Timer? _timer;
  Timer? _clockTimer;
  Timer? _feedsTimer;
  bool _loading = true;
  bool _syncing = false;
  String? _error;
  String _companyTitle = CompanyDisplay.defaultName;
  List<TidsbankenPresence> _presence = [];
  TidsbankenSyncState? _sync;
  List<Absence> _absences = [];
  List<UserProfile> _profiles = [];

  WallboardWeather? _weather;
  List<NrkHeadline> _news = [];
  List<StopDepartures> _transitStops = [];

  Duration get _refreshEvery =>
      widget.refreshInterval ??
      (widget.embedded ? const Duration(minutes: 5) : const Duration(minutes: 2));

  bool get _isWallboard => !widget.embedded;

  @override
  void initState() {
    super.initState();
    _load(trySync: true);
    _loadFeeds();
    _timer = Timer.periodic(_refreshEvery, (_) => _load(trySync: true));
    _feedsTimer = Timer.periodic(const Duration(minutes: 10), (_) => _loadFeeds());
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clockTimer?.cancel();
    _feedsTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadFeeds() async {
    try {
      final results = await Future.wait([
        OpenMeteoWeatherService.fetch(),
        NrkNewsFeedService.fetch(),
        EnturDeparturesService.fetchNearby(),
      ]);
      if (!mounted) return;
      setState(() {
        _weather = results[0] as WallboardWeather?;
        _news = results[1] as List<NrkHeadline>;
        _transitStops = results[2] as List<StopDepartures>;
      });
    } catch (_) {
      // Feeds er nice-to-have — ikke blokker vegg-skjerm.
    }
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

  Future<void> _refreshAll() async {
    await Future.wait([_load(trySync: true), _loadFeeds()]);
  }

  List<TidsbankenPresence> get _clockedIn =>
      _presence.where((p) => p.isClockedIn).toList()
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
      ));
    }
    out.sort((a, b) => a.daysUntil.compareTo(b.daysUntil));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final body = ColoredBox(
      color: _isWallboard ? _bg : (Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0F1419)
          : const Color(0xFFF4F6F8)),
      child: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: DriftProTheme.primaryGreen),
              )
            : Column(
                children: [
                  _header(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                      child: _errorStrip(_error!),
                    ),
                  if (_isWallboard) WallboardExtrasBar(weather: _weather, stops: _transitStops),
                  Expanded(child: _mainBoard()),
                  if (_isWallboard) WallboardNewsTicker(headlines: _news),
                ],
              ),
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(backgroundColor: _bg, body: body);
  }

  Widget _header() {
    final sync = _sync;
    final timeFmt = DateFormat('HH:mm', 'nb');
    final dateFmt = DateFormat('EEEE d. MMMM', 'nb');
    final now = DateTime.now();
    final onJob = sync != null && sync.totalCount > 0
        ? '${sync.clockedInCount} / ${sync.totalCount} innstemplt'
        : '${_clockedIn.length} på jobb';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [WallboardPalette.headerStart, WallboardPalette.headerEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: WallboardPalette.headerShadow.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.dashboard_customize_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _companyTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  onJob,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                if (_isWallboard)
                  const Text(
                    'Live oversikt',
                    style: TextStyle(color: Colors.white38, fontSize: 10),
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
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: 'Oppdater',
                      onPressed: _refreshAll,
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  Text(
                    timeFmt.format(now),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 1.2,
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
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 9),
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
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.orange)),
    );
  }

  Widget _mainBoard() {
    if (_isWallboard) {
      return _wallboardMainLayout();
    }

    final tiles = <_PanelData>[
      _PanelData(
        title: 'På jobb nå',
        icon: Icons.groups_rounded,
        accent: WallboardPalette.onJob,
        count: _clockedIn.length,
        lines: _clockedIn
            .map((p) => _LineItem(
                  title: p.fullName,
                  subtitle: p.sinceTime != null ? 'Siden ${p.sinceTime}' : 'Innstemplt',
                ))
            .toList(),
        empty: 'Ingen innstemplt akkurat nå',
        large: true,
      ),
      _PanelData(
        title: 'Ferie nå',
        icon: Icons.beach_access_rounded,
        accent: WallboardPalette.vacationNow,
        count: _vacationNow.length,
        lines: _vacationLines(_vacationNow, soon: false),
        empty: 'Ingen på ferie i dag',
      ),
      _PanelData(
        title: 'Ferie snart',
        icon: Icons.flight_takeoff_rounded,
        accent: WallboardPalette.vacationSoon,
        count: _vacationSoon.length,
        lines: _vacationLines(_vacationSoon, soon: true),
        empty: 'Ingen planlagt ferie (90 d)',
      ),
      _PanelData(
        title: 'Bursdag i dag',
        icon: Icons.cake_rounded,
        accent: WallboardPalette.birthdayToday,
        count: _birthdaysToday.length,
        lines: _birthdayLines(_birthdaysToday, today: true),
        empty: 'Ingen bursdag i dag',
      ),
      _PanelData(
        title: 'Bursdag snart',
        icon: Icons.celebration_rounded,
        accent: WallboardPalette.birthdaySoon,
        count: _birthdaysSoon.length,
        lines: _birthdayLines(_birthdaysSoon, today: false),
        empty: 'Ingen innen 30 dager',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 900;
          if (!wide) {
            return GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.05,
              ),
              itemCount: tiles.length,
              itemBuilder: (_, i) => _panelCard(tiles[i]),
            );
          }

          final hero = tiles.first;
          final rest = tiles.sublist(1);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 5, child: _panelCard(hero)),
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: _panelCard(rest[0])),
                          const SizedBox(width: 10),
                          Expanded(child: _panelCard(rest[1])),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: _panelCard(rest[2])),
                          const SizedBox(width: 10),
                          Expanded(child: _panelCard(rest[3])),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Fullskjerm vegg: alle på jobb i stort rutenett, øvrig info som kompakte striper.
  Widget _wallboardMainLayout() {
    final onJobNames = _clockedIn.map((p) => p.fullName).toList();
    final onJobSubs = _clockedIn
        .map((p) => p.sinceTime != null ? 'Siden ${p.sinceTime}' : 'Innstemplt')
        .toList();

    final strips = <_PanelData>[
      _PanelData(
        title: 'Ferie nå',
        icon: Icons.beach_access_rounded,
        accent: WallboardPalette.vacationNow,
        count: _vacationNow.length,
        lines: _vacationLines(_vacationNow, soon: false),
        empty: 'Ingen på ferie',
      ),
      _PanelData(
        title: 'Ferie snart',
        icon: Icons.flight_takeoff_rounded,
        accent: WallboardPalette.vacationSoon,
        count: _vacationSoon.length,
        lines: _vacationLines(_vacationSoon, soon: true),
        empty: 'Ingen planlagt',
      ),
      _PanelData(
        title: 'Bursdag i dag',
        icon: Icons.cake_rounded,
        accent: WallboardPalette.birthdayToday,
        count: _birthdaysToday.length,
        lines: _birthdayLines(_birthdaysToday, today: true),
        empty: 'Ingen i dag',
      ),
      _PanelData(
        title: 'Bursdag snart',
        icon: Icons.celebration_rounded,
        accent: WallboardPalette.birthdaySoon,
        count: _birthdaysSoon.length,
        lines: _birthdayLines(_birthdaysSoon, today: false),
        empty: 'Ingen snart',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: LayoutBuilder(
        builder: (context, c) {
          final stripH = (c.maxHeight * 0.16).clamp(72.0, 110.0);
          return Column(
            children: [
              Expanded(
                child: _onJobHeroPanel(
                  names: onJobNames,
                  subtitles: onJobSubs,
                  count: _clockedIn.length,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: stripH,
                child: Row(
                  children: [
                    for (var i = 0; i < strips.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: _compactStripCard(strips[i])),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _onJobHeroPanel({
    required List<String> names,
    required List<String?> subtitles,
    required int count,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WallboardPalette.onJob.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  WallboardPalette.onJob.withValues(alpha: 0.2),
                  WallboardPalette.onJob.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                const Icon(Icons.groups_rounded, color: WallboardPalette.onJob, size: 26),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'På jobb nå — alle synlige',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: WallboardPalette.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: WallboardPalette.onJob.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: WallboardPalette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: WallboardAdaptivePeopleGrid(
              names: names,
              subtitles: subtitles,
              accent: WallboardPalette.onJob,
              dense: names.length > 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactStripCard(_PanelData data) {
    final preview = data.lines.take(2).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: data.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(data.icon, size: 16, color: data.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    color: WallboardPalette.textPrimary,
                  ),
                ),
              ),
              Text(
                '${data.count}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: data.accent,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (preview.isEmpty)
            Text(
              data.empty,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9, color: WallboardPalette.textMuted),
            )
          else
            ...preview.map(
              (line) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  line.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: WallboardPalette.textSecondary,
                  ),
                ),
              ),
            ),
          if (data.lines.length > preview.length)
            Text(
              '+ ${data.lines.length - preview.length} til',
              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: data.accent),
            ),
        ],
      ),
    );
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
          ? 'Bursdag i dag 🎂'
          : e.daysUntil == 1
              ? 'Bursdag i morgen'
              : 'Bursdag om ${e.daysUntil} dager';
      return _LineItem(title: e.profile.fullName, subtitle: label);
    }).toList();
  }

  Widget _smallPanelBody(_PanelData data) {
    final lines = data.lines;
    if (lines.isEmpty) {
      return Center(
        child: Text(
          data.empty,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: WallboardPalette.textMuted),
        ),
      );
    }
    return WallboardAdaptivePeopleGrid(
      names: lines.map((l) => l.title).toList(),
      subtitles: lines.map((l) => l.subtitle).toList(),
      accent: data.accent,
      dense: true,
    );
  }

  Widget _panelCard(_PanelData data) {
    final lines = data.lines;

    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: data.accent.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  data.accent.withValues(alpha: 0.16),
                  data.accent.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                Icon(data.icon, color: data.accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    data.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: WallboardPalette.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: data.accent.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${data.count}',
                    style: const TextStyle(
                      color: WallboardPalette.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: data.large
                ? WallboardAdaptivePeopleGrid(
                    names: lines.map((l) => l.title).toList(),
                    subtitles: lines.map((l) => l.subtitle).toList(),
                    accent: data.accent,
                    dense: lines.length > 16,
                  )
                : _smallPanelBody(data),
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
  final bool large;

  _PanelData({
    required this.title,
    required this.icon,
    required this.accent,
    required this.count,
    required this.lines,
    required this.empty,
    this.large = false,
  });
}

class _LineItem {
  final String title;
  final String? subtitle;

  _LineItem({required this.title, this.subtitle});
}
