import 'package:flutter/material.dart';

import '../../../core/theme/wallboard_palette.dart';

/// Fyller tilgjengelig flate med alle navn — ingen scroll, auto-skalert tekst.
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

  static int _pickColumnCount({
    required int count,
    required double width,
    required double height,
    required bool dense,
  }) {
    if (count <= 0) return 1;
    const pad = 8.0;
    final minW = dense ? 56.0 : 72.0;
    final minH = dense ? 22.0 : 28.0;
    final innerW = width - pad * 2;
    final innerH = height - pad * 2;

    var bestCols = 1;
    var bestScore = 0.0;

    for (var cols = 1; cols <= count; cols++) {
      final rows = (count + cols - 1) ~/ cols;
      final cellW = innerW / cols;
      final cellH = innerH / rows;
      if (cellW < minW || cellH < minH) continue;
      final score = cellW * cellH;
      if (score > bestScore) {
        bestScore = score;
        bestCols = cols;
      }
    }

    if (bestScore == 0) {
      bestCols = count;
      while (bestCols > 1) {
        final rows = (count + bestCols - 1) ~/ bestCols;
        if (innerW / bestCols >= 40 && innerH / rows >= 18) break;
        bestCols--;
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
        final cols = _pickColumnCount(
          count: names.length,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          dense: dense,
        );
        final rows = (names.length + cols - 1) ~/ cols;
        final cellW = constraints.maxWidth / cols;
        final cellH = constraints.maxHeight / rows;
        final aspect = (cellW / cellH).clamp(0.85, 4.5);
        final nameSize = (cellH * (dense ? 0.34 : 0.38)).clamp(dense ? 8.0 : 9.0, dense ? 12.0 : 15.0);
        final subSize = (nameSize * 0.78).clamp(7.0, 11.0);
        final useInitialsOnly = names.length > 36 || (cellW < 64 && names.length > 18);

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(6),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: aspect,
          ),
          itemCount: names.length,
          itemBuilder: (context, i) {
            final name = names[i];
            final sub = i < subtitles.length ? subtitles[i] : null;
            final initials = _initials(name);

            return DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accent.withValues(alpha: 0.2)),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: useInitialsOnly ? 4 : 6,
                  vertical: useInitialsOnly ? 3 : 4,
                ),
                child: useInitialsOnly
                    ? Row(
                        children: [
                          _initialBadge(initials, accent, cellH),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              _shortName(name),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: nameSize,
                                fontWeight: FontWeight.w700,
                                height: 1.05,
                                color: WallboardPalette.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            name,
                            maxLines: dense ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: nameSize,
                              fontWeight: FontWeight.w700,
                              height: 1.05,
                              color: WallboardPalette.textPrimary,
                            ),
                          ),
                          if (sub != null && sub.isNotEmpty && cellH >= 32)
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
            );
          },
        );
      },
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

  static String _shortName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length <= 1) return name;
    return '${parts.first} ${parts.last[0]}.';
  }

  static Widget _initialBadge(String initials, Color accent, double cellH) {
    final size = (cellH * 0.55).clamp(18.0, 28.0);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: (size * 0.38).clamp(8.0, 11.0),
          fontWeight: FontWeight.w800,
          color: WallboardPalette.textPrimary,
        ),
      ),
    );
  }
}
