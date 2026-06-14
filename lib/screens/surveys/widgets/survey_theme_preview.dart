import 'package:flutter/material.dart';

import '../../../core/services/survey/survey_living_motion.dart';
import '../../../core/services/survey/survey_theme_presets.dart';
import 'survey_living_background.dart';

/// Visuell forhåndsvisning av et respondent-tema — ikke bare farger.
class SurveyThemePreviewCard extends StatelessWidget {
  const SurveyThemePreviewCard({
    super.key,
    required this.preset,
    required this.selected,
    this.compact = false,
    this.showLabels = true,
    this.onTap,
  });

  final SurveyThemePreset preset;
  final bool selected;
  final bool compact;
  /// Vis navn/kategori inne i kortet. Slå av for stor «aktivt tema»-forhåndsvisning.
  final bool showLabels;
  final VoidCallback? onTap;

  Color _hex(String h, [Color fallback = Colors.grey]) {
    final c = h.replaceAll('#', '');
    final v = int.tryParse('FF$c', radix: 16);
    return v != null ? Color(v) : fallback;
  }

  @override
  Widget build(BuildContext context) {
    final primary = _hex(preset.primaryHex);
    final bg = _hex(preset.backgroundHex);
    final card = _hex(preset.cardHex);
    final text = _hex(preset.textHex);
    final accent = _hex(preset.accentHex);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(compact ? 12 : 16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: compact ? 100 : (showLabels ? 148 : 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(compact ? 12 : 16),
          border: Border.all(color: selected ? primary : Colors.grey.withValues(alpha: 0.25), width: selected ? 2.5 : 1),
          boxShadow: selected
              ? [BoxShadow(color: primary.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 11 : 15),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildBackground(bg, primary, accent),
              Padding(
                padding: EdgeInsets.all(compact ? 10 : 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _miniLogo(primary, accent),
                        const Spacer(),
                        if (selected)
                          Icon(Icons.check_circle, size: compact ? 16 : 20, color: primary),
                      ],
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _mockQuestionCard(card, text, primary, accent),
                          SizedBox(height: compact ? 4 : 6),
                          _mockButton(primary, text),
                          if (!compact && showLabels) ...[
                            const SizedBox(height: 6),
                            Text(
                              preset.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: text),
                            ),
                            Text(
                              '${preset.category} · ${preset.visualStyleLabel}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10, color: text.withValues(alpha: 0.65)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackground(Color bg, Color primary, Color accent) {
    switch (preset.visualStyle) {
      case SurveyVisualStyle.glass:
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [primary.withValues(alpha: 0.35), bg, accent.withValues(alpha: 0.2)],
            ),
          ),
        );
      case SurveyVisualStyle.gradient:
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [primary.withValues(alpha: preset.darkMode ? 0.5 : 0.25), bg, accent.withValues(alpha: 0.35)],
            ),
          ),
        );
      case SurveyVisualStyle.neon:
        return Container(
          color: bg,
          child: CustomPaint(painter: _NeonGridPainter(primary.withValues(alpha: 0.15))),
        );
      case SurveyVisualStyle.minimal:
        return Container(color: bg);
      case SurveyVisualStyle.bold:
        return Container(
          decoration: BoxDecoration(
            color: bg,
            border: Border(left: BorderSide(color: primary, width: 6)),
          ),
        );
      case SurveyVisualStyle.classic:
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [bg, primary.withValues(alpha: 0.06)],
            ),
          ),
        );
      case SurveyVisualStyle.living:
        return SurveyLivingBackground(
          motion: preset.id.livingMotionFromPresetId,
          background: bg,
          primary: primary,
          accent: accent,
          child: const SizedBox.expand(),
        );
    }
  }

  Widget _miniLogo(Color primary, Color accent) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [primary, accent]),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.poll, color: Colors.white, size: 14),
    );
  }

  Widget _mockQuestionCard(Color card, Color text, Color primary, Color accent) {
    final isGlass = preset.visualStyle == SurveyVisualStyle.glass;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isGlass ? card.withValues(alpha: 0.55) : card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primary.withValues(alpha: 0.2)),
        boxShadow: preset.visualStyle == SurveyVisualStyle.bold
            ? [BoxShadow(color: primary.withValues(alpha: 0.12), blurRadius: 6, offset: const Offset(0, 2))]
            : null,
      ),
      child: Row(
        children: [
          Container(width: 24, height: 4, decoration: BoxDecoration(color: text.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(2))),
          const Spacer(),
          Icon(Icons.star, size: 10, color: accent),
        ],
      ),
    );
  }

  Widget _mockButton(Color primary, Color text) {
    final radius = switch (preset.buttonStyle) {
      'pill' => 12.0,
      'square' => 2.0,
      _ => 6.0,
    };
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 52,
        height: 14,
        decoration: BoxDecoration(
          gradient: preset.visualStyle == SurveyVisualStyle.neon
              ? LinearGradient(colors: [primary, primary.withValues(alpha: 0.7)])
              : null,
          color: preset.visualStyle == SurveyVisualStyle.neon ? null : primary,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: preset.visualStyle == SurveyVisualStyle.neon
              ? [BoxShadow(color: primary.withValues(alpha: 0.5), blurRadius: 6)]
              : null,
        ),
      ),
    );
  }
}

class _NeonGridPainter extends CustomPainter {
  _NeonGridPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    for (var x = 0.0; x < size.width; x += 14) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 14) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
