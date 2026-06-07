import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';
import 'department_absence_stats.dart';

Color absenceTypeColor(AbsenceType type) {
  switch (type) {
    case AbsenceType.ferie:
      return DriftProTheme.absenceVacation;
    case AbsenceType.egenmelding:
      return DriftProTheme.absenceSickSelf;
    case AbsenceType.syktBarn:
      return DriftProTheme.absenceSickChild;
    case AbsenceType.permisjon:
      return DriftProTheme.absenceLeave;
    case AbsenceType.sykmelding:
      return DriftProTheme.absenceSickNote;
  }
}

/// Segmentert stolpe for fraværstyper hittil i år.
class AbsenceTypeBreakdownBar extends StatelessWidget {
  final Map<AbsenceType, int> breakdown;
  final int totalDays;
  final Color accent;
  final int year;

  const AbsenceTypeBreakdownBar({
    super.key,
    required this.breakdown,
    required this.totalDays,
    required this.accent,
    required this.year,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (totalDays <= 0 || breakdown.isEmpty) {
      return const SizedBox.shrink();
    }

    final segments = breakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.pie_chart_outline_rounded, size: 14, color: accent),
            const SizedBox(width: 6),
            Text(
              'Fravær i $year',
              style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Text(
              '$totalDays dager',
              style: DriftProTheme.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                for (final seg in segments)
                  Expanded(
                    flex: seg.value,
                    child: Container(color: absenceTypeColor(seg.key)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final seg in segments.take(4))
              _legendChip(seg.key, seg.value, isDark),
          ],
        ),
      ],
    );
  }

  Widget _legendChip(AbsenceType type, int days, bool isDark) {
    final color = absenceTypeColor(type);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          '${type.label} $days',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey[400] : Colors.grey[700],
          ),
        ),
      ],
    );
  }
}

/// Mini sparkline — siste 6 måneder.
class AbsenceMonthlySparkline extends StatelessWidget {
  final List<DepartmentMonthlyAbsencePoint> points;
  final Color accent;

  const AbsenceMonthlySparkline({
    super.key,
    required this.points,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (points.isEmpty) return const SizedBox.shrink();

    final maxDays = points.map((p) => p.days).fold<int>(0, math.max).clamp(1, 999);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.show_chart_rounded, size: 14, color: accent),
            const SizedBox(width: 6),
            Text(
              'Trend 6 mnd',
              style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final p in points)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (p.days > 0)
                          Text(
                            '${p.days}',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: accent,
                              height: 1,
                            ),
                          )
                        else
                          const SizedBox(height: 10),
                        const SizedBox(height: 2),
                        Flexible(
                          child: FractionallySizedBox(
                            heightFactor: (p.days / maxDays).clamp(0.08, 1.0),
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    accent.withValues(alpha: 0.35),
                                    accent,
                                  ],
                                ),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          p.shortLabel,
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.grey[500] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Topp ansatte med mest godkjent fravær — navn + stolpe.
class AbsenceLeaderboard extends StatelessWidget {
  final List<DepartmentMemberAbsenceRank> entries;
  final Color accent;

  const AbsenceLeaderboard({
    super.key,
    required this.entries,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (entries.isEmpty) return const SizedBox.shrink();

    final maxDays = entries.first.totalDaysYtd.clamp(1, 999);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.leaderboard_outlined, size: 14, color: accent),
            const SizedBox(width: 6),
            Text(
              'Mest fravær i år',
              style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _leaderRow(entries[i], i + 1, maxDays, isDark),
        ],
      ],
    );
  }

  Widget _leaderRow(
    DepartmentMemberAbsenceRank entry,
    int rank,
    int maxDays,
    bool isDark,
  ) {
    final type = entry.dominantType;
    final typeColor = type != null ? absenceTypeColor(type) : accent;
    final ratio = (entry.totalDaysYtd / maxDays).clamp(0.0, 1.0);

    return Row(
      children: [
        _rankBadge(rank, isDark),
        const SizedBox(width: 8),
        CircleAvatar(
          radius: 13,
          backgroundColor: typeColor.withValues(alpha: 0.18),
          child: Text(
            entry.initials,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: typeColor,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DriftProTheme.caption.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${entry.totalDaysYtd} d',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: typeColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 5,
                  backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(typeColor),
                ),
              ),
              if (type != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Mest ${type.label.toLowerCase()}',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _rankBadge(int rank, bool isDark) {
    final medals = [DriftProTheme.warning, Colors.grey.shade400, const Color(0xFFCD7F32)];
    final color = rank <= 3 ? medals[rank - 1] : (isDark ? Colors.grey[600]! : Colors.grey[400]!);
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: rank <= 3 ? 0.2 : 0.12),
        shape: BoxShape.circle,
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

/// Halvmåne-donut for fraværsfordeling (dekorativt sammendrag).
class AbsenceTypeDonut extends StatelessWidget {
  final Map<AbsenceType, int> breakdown;
  final int totalDays;
  final Color accent;

  const AbsenceTypeDonut({
    super.key,
    required this.breakdown,
    required this.totalDays,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (totalDays <= 0 || breakdown.isEmpty) return const SizedBox.shrink();

    final segments = breakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SizedBox(
      width: 52,
      height: 52,
      child: CustomPaint(
        painter: _DonutPainter(
          segments: segments,
          strokeWidth: 7,
          gapRadians: 0.04,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$totalDays',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: accent,
                  height: 1,
                ),
              ),
              Text(
                'dager',
                style: TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.w600,
                  color: accent.withValues(alpha: 0.8),
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<MapEntry<AbsenceType, int>> segments;
  final double strokeWidth;
  final double gapRadians;

  _DonutPainter({
    required this.segments,
    required this.strokeWidth,
    required this.gapRadians,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<int>(0, (sum, e) => sum + e.value);
    if (total <= 0) return;

    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    var start = -math.pi / 2;

    for (final seg in segments) {
      final sweep = (seg.value / total) * 2 * math.pi - gapRadians;
      if (sweep <= 0) continue;
      final paint = Paint()
        ..color = absenceTypeColor(seg.key)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep + gapRadians;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.segments != segments;
}
