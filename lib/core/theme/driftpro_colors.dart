import 'package:flutter/material.dart';

/// Semantiske fargetokens — én kilde for lys og mørk modus.
@immutable
class DriftProColors extends ThemeExtension<DriftProColors> {
  const DriftProColors({
    required this.scaffold,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceMuted,
    required this.surfaceOverlay,
    required this.card,
    required this.cardElevated,
    required this.border,
    required this.borderSubtle,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textInverse,
    required this.iconPrimary,
    required this.iconMuted,
    required this.inputFill,
    required this.inputBorder,
    required this.navBar,
    required this.navSelected,
    required this.navUnselected,
    required this.shadow,
    required this.scrim,
    required this.shimmerBase,
    required this.shimmerHighlight,
    required this.heroGradient,
    required this.subtleGradient,
    required this.glassHighlight,
    required this.warningSurface,
    required this.errorSurface,
    required this.successSurface,
    required this.infoSurface,
  });

  final Color scaffold;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceMuted;
  final Color surfaceOverlay;
  final Color card;
  final Color cardElevated;
  final Color border;
  final Color borderSubtle;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textInverse;
  final Color iconPrimary;
  final Color iconMuted;
  final Color inputFill;
  final Color inputBorder;
  final Color navBar;
  final Color navSelected;
  final Color navUnselected;
  final Color shadow;
  final Color scrim;
  final Color shimmerBase;
  final Color shimmerHighlight;
  final Gradient heroGradient;
  final Gradient subtleGradient;
  final Color glassHighlight;
  final Color warningSurface;
  final Color errorSurface;
  final Color successSurface;
  final Color infoSurface;

  List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: shadow.withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: shadow.withValues(alpha: 0.04),
          blurRadius: 32,
          offset: const Offset(0, 10),
        ),
      ];

  List<BoxShadow> get elevatedShadow => [
        BoxShadow(
          color: shadow.withValues(alpha: 0.14),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: shadow.withValues(alpha: 0.06),
          blurRadius: 40,
          offset: const Offset(0, 16),
        ),
      ];

  BoxDecoration surfaceDecoration({double radius = 16, bool elevated = false}) =>
      BoxDecoration(
        color: elevated ? cardElevated : card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderSubtle),
        boxShadow: elevated ? cardShadow : null,
      );

  static const light = DriftProColors(
    scaffold: Color(0xFFF8FAF9),
    surface: Color(0xFFF8FAF9),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF1F5F2),
    surfaceOverlay: Color(0xFFF4F7F5),
    card: Color(0xFFFFFFFF),
    cardElevated: Color(0xFFFFFFFF),
    border: Color(0xFFE0E8E2),
    borderSubtle: Color(0xFFEDF2EE),
    divider: Color(0xFFE0E8E2),
    textPrimary: Color(0xFF0D1F12),
    textSecondary: Color(0xFF3D5244),
    textMuted: Color(0xFF6B7A70),
    textInverse: Color(0xFFFFFFFF),
    iconPrimary: Color(0xFF0D3B13),
    iconMuted: Color(0xFF8A968E),
    inputFill: Color(0xFFF5F7F6),
    inputBorder: Color(0xFFD8E0DA),
    navBar: Color(0xFFFFFFFF),
    navSelected: Color(0xFF1B5E20),
    navUnselected: Color(0xFF9AA89E),
    shadow: Color(0xFF1B5E20),
    scrim: Color(0xFF000000),
    shimmerBase: Color(0xFFE8EDE9),
    shimmerHighlight: Color(0xFFF5F8F6),
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1B5E20), Color(0xFF0D47A1)],
    ),
    subtleGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFF8FAF9), Color(0xFFF1F5F2)],
    ),
    glassHighlight: Color(0xFFFFFFFF),
    warningSurface: Color(0xFFFFF8E1),
    errorSurface: Color(0xFFFFEBEE),
    successSurface: Color(0xFFE8F5E9),
    infoSurface: Color(0xFFE3F2FD),
  );

  static const dark = DriftProColors(
    scaffold: Color(0xFF060A08),
    surface: Color(0xFF0A100C),
    surfaceElevated: Color(0xFF101814),
    surfaceMuted: Color(0xFF0E1410),
    surfaceOverlay: Color(0xFF141C17),
    card: Color(0xFF121A15),
    cardElevated: Color(0xFF182420),
    border: Color(0xFF2A3D32),
    borderSubtle: Color(0xFF1E2E26),
    divider: Color(0xFF243329),
    textPrimary: Color(0xFFF0F4F1),
    textSecondary: Color(0xFFB8C4BB),
    textMuted: Color(0xFF7A8A80),
    textInverse: Color(0xFF060A08),
    iconPrimary: Color(0xFFE8F5EA),
    iconMuted: Color(0xFF6B7A70),
    inputFill: Color(0xFF101814),
    inputBorder: Color(0xFF2A3D32),
    navBar: Color(0xFF0C1210),
    navSelected: Color(0xFF81C784),
    navUnselected: Color(0xFF5A6B60),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    shimmerBase: Color(0xFF141C17),
    shimmerHighlight: Color(0xFF1E2A24),
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0D3B13), Color(0xFF082F6E)],
    ),
    subtleGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0A100C), Color(0xFF060A08)],
    ),
    glassHighlight: Color(0xFFFFFFFF),
    warningSurface: Color(0xFF2A2210),
    errorSurface: Color(0xFF2A1416),
    successSurface: Color(0xFF102A18),
    infoSurface: Color(0xFF0E1E2A),
  );

  @override
  DriftProColors copyWith({
    Color? scaffold,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceMuted,
    Color? surfaceOverlay,
    Color? card,
    Color? cardElevated,
    Color? border,
    Color? borderSubtle,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textInverse,
    Color? iconPrimary,
    Color? iconMuted,
    Color? inputFill,
    Color? inputBorder,
    Color? navBar,
    Color? navSelected,
    Color? navUnselected,
    Color? shadow,
    Color? scrim,
    Color? shimmerBase,
    Color? shimmerHighlight,
    Gradient? heroGradient,
    Gradient? subtleGradient,
    Color? glassHighlight,
    Color? warningSurface,
    Color? errorSurface,
    Color? successSurface,
    Color? infoSurface,
  }) {
    return DriftProColors(
      scaffold: scaffold ?? this.scaffold,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
      card: card ?? this.card,
      cardElevated: cardElevated ?? this.cardElevated,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textInverse: textInverse ?? this.textInverse,
      iconPrimary: iconPrimary ?? this.iconPrimary,
      iconMuted: iconMuted ?? this.iconMuted,
      inputFill: inputFill ?? this.inputFill,
      inputBorder: inputBorder ?? this.inputBorder,
      navBar: navBar ?? this.navBar,
      navSelected: navSelected ?? this.navSelected,
      navUnselected: navUnselected ?? this.navUnselected,
      shadow: shadow ?? this.shadow,
      scrim: scrim ?? this.scrim,
      shimmerBase: shimmerBase ?? this.shimmerBase,
      shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
      heroGradient: heroGradient ?? this.heroGradient,
      subtleGradient: subtleGradient ?? this.subtleGradient,
      glassHighlight: glassHighlight ?? this.glassHighlight,
      warningSurface: warningSurface ?? this.warningSurface,
      errorSurface: errorSurface ?? this.errorSurface,
      successSurface: successSurface ?? this.successSurface,
      infoSurface: infoSurface ?? this.infoSurface,
    );
  }

  @override
  DriftProColors lerp(ThemeExtension<DriftProColors>? other, double t) {
    if (other is! DriftProColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return DriftProColors(
      scaffold: l(scaffold, other.scaffold),
      surface: l(surface, other.surface),
      surfaceElevated: l(surfaceElevated, other.surfaceElevated),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      surfaceOverlay: l(surfaceOverlay, other.surfaceOverlay),
      card: l(card, other.card),
      cardElevated: l(cardElevated, other.cardElevated),
      border: l(border, other.border),
      borderSubtle: l(borderSubtle, other.borderSubtle),
      divider: l(divider, other.divider),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textMuted: l(textMuted, other.textMuted),
      textInverse: l(textInverse, other.textInverse),
      iconPrimary: l(iconPrimary, other.iconPrimary),
      iconMuted: l(iconMuted, other.iconMuted),
      inputFill: l(inputFill, other.inputFill),
      inputBorder: l(inputBorder, other.inputBorder),
      navBar: l(navBar, other.navBar),
      navSelected: l(navSelected, other.navSelected),
      navUnselected: l(navUnselected, other.navUnselected),
      shadow: l(shadow, other.shadow),
      scrim: l(scrim, other.scrim),
      shimmerBase: l(shimmerBase, other.shimmerBase),
      shimmerHighlight: l(shimmerHighlight, other.shimmerHighlight),
      heroGradient: t < 0.5 ? heroGradient : other.heroGradient,
      subtleGradient: t < 0.5 ? subtleGradient : other.subtleGradient,
      glassHighlight: l(glassHighlight, other.glassHighlight),
      warningSurface: l(warningSurface, other.warningSurface),
      errorSurface: l(errorSurface, other.errorSurface),
      successSurface: l(successSurface, other.successSurface),
      infoSurface: l(infoSurface, other.infoSurface),
    );
  }
}
