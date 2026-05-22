import 'package:flutter/material.dart';

import '../../../core/theme/wallboard_palette.dart';

/// Kompakt rutenett — alle navn synlige uten scroll, uten store tomme flater.
class WallboardAdaptivePeopleGrid extends StatelessWidget {
  final List<String> names;
  final List<String?> subtitles;
  final Color accent;
  final bool dense;

  const WallboardAdaptivePeopleGrid({
    super.key,
    required this.names,
    this.subtitles = const [],
    required this.accent,
    this.dense = false,
  });

  static double itemHeight(int count, bool dense) {
    if (dense || count > 24) return 36;
    if (count > 14) return 40;
    if (count > 8) return 44;
    return 48;
  }

  static double gap(int count, bool dense) => dense || count > 14 ? 5 : 6;

  /// Flere kolonner = lavere kort; begrens radhøyde.
  static int pickColumnCount({
    required int count,
    required double width,
    required double itemH,
    required double gapH,
  }) {
    if (count <= 0) return 1;
    const pad = 16.0;
    final innerW = (width - pad).clamp(1, width);
    const minCellW = 118.0;

    var bestCols = 1;
    var bestScore = double.negativeInfinity;

    for (var cols = 1; cols <= count; cols++) {
      final cellW = innerW / cols;
      if (cellW < minCellW) break;

      final rows = (count + cols - 1) ~/ cols;
      final gridH = rows * itemH + (rows - 1) * gapH;
      // Foretrekk flere kolonner (smalere kort), men ikke én ekstrem rad hvis unødvendig.
      final colBonus = cols.toDouble();
      final rowPenalty = rows == 1 && count > 4 ? 0.85 : 1.0;
      final score = colBonus * rowPenalty / (gridH * 0.002 + 1);

      if (score > bestScore) {
        bestScore = score;
        bestCols = cols;
      }
    }

    return bestCols.clamp(1, count);
  }

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) {
      return const Center(
        child: Text(
          'Ingen innstemplt akkurat nå',
          style: TextStyle(fontSize: 13, color: WallboardPalette.textMuted),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemH = itemHeight(names.length, dense);
        final gapH = gap(names.length, dense);
        final cols = pickColumnCount(
          count: names.length,
          width: constraints.maxWidth,
          itemH: itemH,
          gapH: gapH,
        );
        final rows = (names.length + cols - 1) ~/ cols;
        final nameSize = (itemH * 0.38).clamp(11.0, dense ? 14.0 : 15.0);
        final subSize = (nameSize * 0.82).clamp(9.0, 12.0);
        final avatar = (itemH * 0.72).clamp(26.0, 34.0);

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var r = 0; r < rows; r++) ...[
                  if (r > 0) SizedBox(height: gapH),
                  SizedBox(
                    height: itemH,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var c = 0; c < cols; c++) ...[
                          if (c > 0) SizedBox(width: gapH),
                          Expanded(
                            child: _cell(
                              index: r * cols + c,
                              nameSize: nameSize,
                              subSize: subSize,
                              avatar: avatar,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cell({
    required int index,
    required double nameSize,
    required double subSize,
    required double avatar,
  }) {
    if (index >= names.length) {
      return const SizedBox.shrink();
    }
    final name = names[index];
    final sub = index < subtitles.length ? subtitles[index] : null;
    final initials = _initials(name);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Container(
              width: avatar,
              height: avatar,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: avatar * 0.38,
                  fontWeight: FontWeight.w800,
                  color: WallboardPalette.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: nameSize,
                      fontWeight: FontWeight.w700,
                      height: 1.05,
                      color: WallboardPalette.textPrimary,
                    ),
                  ),
                  if (sub != null && sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: subSize,
                        color: WallboardPalette.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final p = parts.first;
      return p.length >= 2 ? p.substring(0, 2).toUpperCase() : p.toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
