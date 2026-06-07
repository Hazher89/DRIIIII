import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/absence_palette.dart';
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

/// Segmentert stolpe for fraværstyper — én linje med prosent.
class AbsenceTypeBreakdownBar extends StatelessWidget {
  final Map<AbsenceType, int> breakdown;
  final int totalDays;

  const AbsenceTypeBreakdownBar({
    super.key,
    required this.breakdown,
    required this.totalDays,
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 12,
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
          spacing: 10,
          runSpacing: 6,
          children: [
            for (final seg in segments)
              _legendChip(seg.key, seg.value, totalDays, isDark),
          ],
        ),
      ],
    );
  }

  Widget _legendChip(AbsenceType type, int days, int total, bool isDark) {
    final color = absenceTypeColor(type);
    final pct = total > 0 ? ((days / total) * 100).round() : 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            '${type.label}  $days d  ($pct%)',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.grey[300] : Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }
}

/// Topp ansatte med mest registrert fravær.
class AbsenceLeaderboard extends StatelessWidget {
  final List<DepartmentMemberAbsenceRank> entries;

  const AbsenceLeaderboard({
    super.key,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Topp ${entries.length}',
              style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Text(
              'Dager totalt',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: AbsencePalette.slate,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _leaderRow(entries[i], i + 1, isDark),
        ],
      ],
    );
  }

  Widget _leaderRow(
    DepartmentMemberAbsenceRank entry,
    int rank,
    bool isDark,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 16,
          child: Text(
            '$rank.',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: AbsencePalette.rankColor(rank, isDark),
            ),
          ),
        ),
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
                      style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${entry.totalDaysYtd} d',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AbsencePalette.slateDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 6,
                  child: Row(
                    children: [
                      if (entry.egenDays > 0)
                        Expanded(
                          flex: entry.egenDays,
                          child: ColoredBox(color: DriftProTheme.absenceSickSelf),
                        ),
                      if (entry.syktDays > 0)
                        Expanded(
                          flex: entry.syktDays,
                          child: ColoredBox(color: DriftProTheme.absenceSickChild),
                        ),
                      if (entry.totalDaysYtd <= 0)
                        Expanded(child: ColoredBox(color: Colors.grey.shade200)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _detailLabel(entry),
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _detailLabel(DepartmentMemberAbsenceRank entry) {
    final parts = <String>[];
    if (entry.egenDays > 0) {
      parts.add('${entry.egenDays} d egen');
      if (entry.egenTilfeller > 0) {
        parts.add('${entry.egenTilfeller} tilf.');
      }
    }
    if (entry.syktDays > 0) parts.add('${entry.syktDays} d sykt barn');
    return parts.isEmpty ? 'Ingen registrert' : parts.join(' · ');
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
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: AbsencePalette.slateDark,
                  height: 1,
                ),
              ),
              Text(
                'dager',
                style: TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.w600,
                  color: AbsencePalette.slate.withValues(alpha: 0.9),
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
