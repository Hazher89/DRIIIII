import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import 'drive_monitor_map_view.dart';

enum DriveStatsPeriod { day, week, month, year }

/// Smart statistikk per enhet: dag / uke / måned / år.
class DriveMonitorStatsPanel extends StatefulWidget {
  const DriveMonitorStatsPanel({
    super.key,
    required this.companyId,
    required this.devices,
    required this.sessions,
    required this.events,
  });

  final String companyId;
  final List<Map<String, dynamic>> devices;
  final List<Map<String, dynamic>> sessions;
  final List<Map<String, dynamic>> events;

  @override
  State<DriveMonitorStatsPanel> createState() => _DriveMonitorStatsPanelState();
}

class _DriveMonitorStatsPanelState extends State<DriveMonitorStatsPanel> {
  DriveStatsPeriod _period = DriveStatsPeriod.day;
  String? _unitId; // device_profile_id
  DateTime _anchor = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.devices.isNotEmpty) {
      _unitId = widget.devices.first['id'] as String?;
    }
  }

  @override
  void didUpdateWidget(covariant DriveMonitorStatsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_unitId == null && widget.devices.isNotEmpty) {
      _unitId = widget.devices.first['id'] as String?;
    }
  }

  (DateTime start, DateTime end) get _range {
    final a = DateTime(_anchor.year, _anchor.month, _anchor.day);
    switch (_period) {
      case DriveStatsPeriod.day:
        return (a, a.add(const Duration(days: 1)));
      case DriveStatsPeriod.week:
        final monday = a.subtract(Duration(days: a.weekday - 1));
        return (monday, monday.add(const Duration(days: 7)));
      case DriveStatsPeriod.month:
        final start = DateTime(a.year, a.month, 1);
        return (start, DateTime(a.year, a.month + 1, 1));
      case DriveStatsPeriod.year:
        return (DateTime(a.year, 1, 1), DateTime(a.year + 1, 1, 1));
    }
  }

  String get _rangeLabel {
    final (s, e) = _range;
    final df = DateFormat('dd.MM.yyyy');
    switch (_period) {
      case DriveStatsPeriod.day:
        return df.format(s);
      case DriveStatsPeriod.week:
        return '${df.format(s)} – ${df.format(e.subtract(const Duration(days: 1)))}';
      case DriveStatsPeriod.month:
        const months = [
          '', 'Januar', 'Februar', 'Mars', 'April', 'Mai', 'Juni',
          'Juli', 'August', 'September', 'Oktober', 'November', 'Desember',
        ];
        return '${months[s.month]} ${s.year}';
      case DriveStatsPeriod.year:
        return '${s.year}';
    }
  }

  List<Map<String, dynamic>> get _unitSessions {
    final (start, end) = _range;
    return widget.sessions.where((s) {
      if (_unitId != null && s['device_profile_id'] != _unitId) return false;
      final t = DateTime.tryParse('${s['started_at']}')?.toLocal();
      if (t == null) return false;
      return !t.isBefore(start) && t.isBefore(end);
    }).toList();
  }

  List<Map<String, dynamic>> get _unitEvents {
    final sessionIds = _unitSessions.map((s) => s['id']).toSet();
    final (start, end) = _range;
    return widget.events.where((e) {
      if (_unitId != null) {
        if (!sessionIds.contains(e['session_id'])) return false;
      }
      final t = DateTime.tryParse('${e['recorded_at']}')?.toLocal();
      if (t == null) return false;
      return !t.isBefore(start) && t.isBefore(end);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sessions = _unitSessions;
    final events = _unitEvents;

    final km = sessions.fold<double>(
      0,
      (s, e) => s + ((e['km'] as num?)?.toDouble() ?? 0),
    );
    final rough = events.where((e) => e['severity'] == 'rough').length;
    final hardBrake =
        events.where((e) => e['event_type'] == 'hard_brake').length;
    final hardAccel =
        events.where((e) => e['event_type'] == 'hard_accel').length;
    final sharpTurn =
        events.where((e) => e['event_type'] == 'sharp_turn').length;
    final speeding =
        events.where((e) => e['event_type'] == 'speeding').length;
    final idle = events.where((e) => e['event_type'] == 'idle').length;
    final maxSpeed = sessions.fold<double>(0, (s, e) {
      final v = (e['max_speed_kmh'] as num?)?.toDouble() ?? 0;
      return v > s ? v : s;
    });
    final avgScore = sessions.isEmpty
        ? 100.0
        : sessions.fold<double>(
              0,
              (s, e) => s + ((e['score'] as num?)?.toDouble() ?? 100),
            ) /
            sessions.length;

    final unitLabel = () {
      if (_unitId == null) return 'Alle enheter';
      for (final d in widget.devices) {
        if (d['id'] == _unitId) {
          final n = (d['drive_monitor_unit_name'] as String?)?.trim();
          if (n != null && n.isNotEmpty) return n;
          return '${d['full_name'] ?? 'Enhet'}';
        }
      }
      return 'Enhet';
    }();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined,
                  color: DriftProTheme.primaryGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Smart statistikk',
                  style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<DriveStatsPeriod>(
            segments: const [
              ButtonSegment(value: DriveStatsPeriod.day, label: Text('Dag')),
              ButtonSegment(value: DriveStatsPeriod.week, label: Text('Uke')),
              ButtonSegment(value: DriveStatsPeriod.month, label: Text('Mnd')),
              ButtonSegment(value: DriveStatsPeriod.year, label: Text('År')),
            ],
            selected: {_period},
            onSelectionChanged: (s) => setState(() => _period = s.first),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                onPressed: () => setState(() {
                  switch (_period) {
                    case DriveStatsPeriod.day:
                      _anchor = _anchor.subtract(const Duration(days: 1));
                    case DriveStatsPeriod.week:
                      _anchor = _anchor.subtract(const Duration(days: 7));
                    case DriveStatsPeriod.month:
                      _anchor = DateTime(_anchor.year, _anchor.month - 1, 1);
                    case DriveStatsPeriod.year:
                      _anchor = DateTime(_anchor.year - 1, 1, 1);
                  }
                }),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  _rangeLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: () => setState(() {
                  switch (_period) {
                    case DriveStatsPeriod.day:
                      _anchor = _anchor.add(const Duration(days: 1));
                    case DriveStatsPeriod.week:
                      _anchor = _anchor.add(const Duration(days: 7));
                    case DriveStatsPeriod.month:
                      _anchor = DateTime(_anchor.year, _anchor.month + 1, 1);
                    case DriveStatsPeriod.year:
                      _anchor = DateTime(_anchor.year + 1, 1, 1);
                  }
                }),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (widget.devices.isNotEmpty) ...[
            DropdownButtonFormField<String?>(
              value: _unitId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Enhet',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Alle enheter')),
                ...widget.devices.map((d) {
                  final n = (d['drive_monitor_unit_name'] as String?)?.trim();
                  final label =
                      (n != null && n.isNotEmpty) ? n : '${d['full_name']}';
                  return DropdownMenuItem(
                    value: d['id'] as String?,
                    child: Text(label),
                  );
                }),
              ],
              onChanged: (v) => setState(() => _unitId = v),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            unitLabel,
            style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final w = (c.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statTile(w, 'Km kjørt', km.toStringAsFixed(1), const Color(0xFF0EA5E9)),
                  _statTile(w, 'Sesjoner', '${sessions.length}', DriftProTheme.primaryGreen),
                  _statTile(w, 'Score', avgScore.toStringAsFixed(0), const Color(0xFF8B5CF6)),
                  _statTile(w, 'Maks fart', '${maxSpeed.toStringAsFixed(0)}', const Color(0xFFF59E0B)),
                  _statTile(w, 'Rå hendelser', '$rough', const Color(0xFFDC2626)),
                  _statTile(w, 'Rå brems', '$hardBrake', const Color(0xFFEA580C)),
                  _statTile(w, 'Rå aksel.', '$hardAccel', const Color(0xFFCA8A04)),
                  _statTile(w, 'Rå sving', '$sharpTurn', const Color(0xFF7C3AED)),
                  _statTile(w, 'Fart', '$speeding', const Color(0xFFEF4444)),
                  _statTile(w, 'Stillstand', '$idle', const Color(0xFF64748B)),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _barChart(
            isDark,
            [
              _Bar('Brems', hardBrake, DriveMonitorMapView.eventColor('hard_brake', 'rough')),
              _Bar('Aksel.', hardAccel, DriveMonitorMapView.eventColor('hard_accel', 'warning')),
              _Bar('Sving', sharpTurn, DriveMonitorMapView.eventColor('sharp_turn', 'rough')),
              _Bar('Fart', speeding, DriveMonitorMapView.eventColor('speeding', 'warning')),
              _Bar('Idle', idle, DriveMonitorMapView.eventColor('idle', 'info')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTile(double width, String label, String value, Color color) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.16),
              color.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: DriftProTheme.caption),
          ],
        ),
      ),
    );
  }

  Widget _barChart(bool isDark, List<_Bar> bars) {
    final max = bars.fold<int>(1, (m, b) => b.n > m ? b.n : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Hendelser i perioden',
          style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ...bars.map((b) {
          final frac = b.n / max;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(b.label, style: DriftProTheme.caption),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: frac,
                      minHeight: 12,
                      backgroundColor: isDark
                          ? Colors.white10
                          : Colors.grey.shade100,
                      valueColor: AlwaysStoppedAnimation(b.color),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${b.n}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _Bar {
  const _Bar(this.label, this.n, this.color);
  final String label;
  final int n;
  final Color color;
}
