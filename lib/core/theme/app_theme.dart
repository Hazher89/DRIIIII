import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'driftpro_colors.dart';

class DriftProTheme {
  // ── Brand Colors ──
  static const Color primaryGreen = Color(0xFF1B5E20);
  static const Color primaryGreenLight = Color(0xFF2E7D32);
  static const Color primaryGreenDark = Color(0xFF0D3B13);
  static const Color accentBlue = Color(0xFF0D47A1);
  static const Color accentBlueLight = Color(0xFF1565C0);
  static const Color accentBlueDark = Color(0xFF082F6E);

  // ── Semantic Colors ──
  static const Color success = Color(0xFF43A047);
  static const Color warning = Color(0xFFFFA726);
  static const Color error = Color(0xFFE53935);
  static const Color info = Color(0xFF29B6F6);
  static const Color bgLight = Color(0xFFF8F9FA);
  static const Color bgDark = Color(0xFF060A08);

  // ── Risk Matrix Colors ──
  static const Color riskLow = Color(0xFF66BB6A);
  static const Color riskMedium = Color(0xFFFFCA28);
  static const Color riskHigh = Color(0xFFFF7043);
  static const Color riskCritical = Color(0xFFEF5350);
  static const Color riskExtreme = Color(0xFFB71C1C);

  // ── Severity Colors ──
  static const Color severityLow = Color(0xFF66BB6A);
  static const Color severityMedium = Color(0xFFFFA726);
  static const Color severityHigh = Color(0xFFFF7043);
  static const Color severityCritical = Color(0xFFE53935);

  // ── Absence Type Colors ──
  static const Color absenceVacation = Color(0xFF6366F1);
  static const Color absenceSickSelf = Color(0xFF8B5CF6);
  static const Color absenceSickChild = Color(0xFF0EA5E9);
  static const Color absenceLeave = Color(0xFFA78BFA);
  static const Color absenceSickNote = Color(0xFFEC4899);

  // ── Neutral Colors (bakoverkompatibilitet) ──
  static const Color surfaceLight = Color(0xFFF8FAF9);
  static const Color surfaceDark = Color(0xFF0A100C);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF121A15);
  static const Color dividerLight = Color(0xFFE0E8E2);
  static const Color dividerDark = Color(0xFF243329);

  // ── Gradients ──
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryGreen, accentBlue],
  );

  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0D3B13), Color(0xFF082F6E)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1F3D22), Color(0xFF0E3466)],
  );

  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF43A047), Color(0xFF66BB6A)],
  );

  // ── Border Radius ──
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double radiusRound = 100.0;

  // ── Spacing ──
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;
  static const double spacing2Xl = 48.0;

  static List<BoxShadow> cardShadowFor(bool isDark) =>
      (isDark ? DriftProColors.dark : DriftProColors.light).cardShadow;

  static List<BoxShadow> elevatedShadowFor(bool isDark) =>
      (isDark ? DriftProColors.dark : DriftProColors.light).elevatedShadow;

  @Deprecated('Use context.driftColors.cardShadow')
  static List<BoxShadow> get cardShadow => DriftProColors.light.cardShadow;

  @Deprecated('Use context.driftColors.elevatedShadow')
  static List<BoxShadow> get elevatedShadow => DriftProColors.light.elevatedShadow;

  // ── Text Styles ──
  static TextStyle get headingXl => GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      );

  static TextStyle get headingLg => GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      );

  static TextStyle get headingMd => GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      );

  static TextStyle get headingSm => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get bodyLg => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
      );

  static TextStyle get bodyMd => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
      );

  static TextStyle get bodySm => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.4,
      );

  static TextStyle get labelLg => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      );

  static TextStyle get labelSm => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      );

  static TextStyle get labelMd => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      );

  static TextStyle captionFor(Color color) => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: color,
      );

  static TextStyle get caption => captionFor(const Color(0xFF6B7A70));

  static TextStyle get statNumber => GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
      );

  static ThemeData get lightTheme => _buildTheme(
        brightness: Brightness.light,
        scheme: _lightScheme,
        drift: DriftProColors.light,
      );

  static ThemeData get darkTheme => _buildTheme(
        brightness: Brightness.dark,
        scheme: _darkScheme,
        drift: DriftProColors.dark,
      );

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: primaryGreen,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFC8E6C9),
    onPrimaryContainer: primaryGreenDark,
    secondary: accentBlue,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFBBDEFB),
    onSecondaryContainer: accentBlueDark,
    tertiary: Color(0xFF00897B),
    onTertiary: Colors.white,
    error: error,
    onError: Colors.white,
    surface: surfaceLight,
    onSurface: Color(0xFF0D1F12),
    onSurfaceVariant: Color(0xFF3D5244),
    outline: dividerLight,
    outlineVariant: Color(0xFFEDF2EE),
    shadow: Color(0xFF1B5E20),
    scrim: Colors.black,
    inverseSurface: Color(0xFF1A2420),
    onInverseSurface: Color(0xFFE8F0EA),
    inversePrimary: Color(0xFF81C784),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFF4F7F5),
    surfaceContainer: Color(0xFFEDF2EE),
    surfaceContainerHigh: Color(0xFFE8EDE9),
    surfaceContainerHighest: Color(0xFFE0E8E2),
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF81C784),
    onPrimary: Color(0xFF0A1F0E),
    primaryContainer: Color(0xFF1B4332),
    onPrimaryContainer: Color(0xFFB7F5C3),
    secondary: Color(0xFF64B5F6),
    onSecondary: Color(0xFF082F6E),
    secondaryContainer: Color(0xFF0E3466),
    onSecondaryContainer: Color(0xFFBBDEFB),
    tertiary: Color(0xFF4DB6AC),
    onTertiary: Color(0xFF003731),
    error: Color(0xFFFF8A80),
    onError: Color(0xFF4A0002),
    surface: Color(0xFF0A100C),
    onSurface: Color(0xFFF0F4F1),
    onSurfaceVariant: Color(0xFFB8C4BB),
    outline: Color(0xFF2A3D32),
    outlineVariant: Color(0xFF1E2E26),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: Color(0xFFE8F0EA),
    onInverseSurface: Color(0xFF0D1F12),
    inversePrimary: primaryGreen,
    surfaceContainerLowest: Color(0xFF060A08),
    surfaceContainerLow: Color(0xFF0E1410),
    surfaceContainer: Color(0xFF121A15),
    surfaceContainerHigh: Color(0xFF161F19),
    surfaceContainerHighest: Color(0xFF1E2A24),
  );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required ColorScheme scheme,
    required DriftProColors drift,
  }) {
    final isDark = brightness == Brightness.dark;
    final baseText = GoogleFonts.interTextTheme(
      isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: drift.scaffold,
      cardColor: drift.card,
      dividerColor: drift.divider,
      canvasColor: drift.surface,
      shadowColor: drift.shadow,
      extensions: [drift],
      textTheme: baseText.apply(
        bodyColor: drift.textPrimary,
        displayColor: drift.textPrimary,
      ),
      iconTheme: IconThemeData(color: drift.iconPrimary, size: 22),
      primaryIconTheme: IconThemeData(color: scheme.primary, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: headingMd.copyWith(color: drift.textPrimary),
        iconTheme: IconThemeData(color: drift.iconPrimary),
        actionsIconTheme: IconThemeData(color: drift.iconPrimary),
        systemOverlayStyle: isDark
            ? const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
              )
            : const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
              ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: drift.navBar,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.14),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return labelSm.copyWith(
            color: selected ? drift.navSelected : drift.navUnselected,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? drift.navSelected : drift.navUnselected,
            size: 22,
          );
        }),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: drift.navBar,
        selectedItemColor: drift.navSelected,
        unselectedItemColor: drift.navUnselected,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: labelSm,
        unselectedLabelStyle: labelSm,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: drift.textMuted,
        indicatorColor: scheme.primary,
        dividerColor: drift.divider,
        labelStyle: labelMd,
        unselectedLabelStyle: bodySm,
        overlayColor: WidgetStateProperty.all(scheme.primary.withValues(alpha: 0.08)),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: drift.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(radiusXl)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: drift.iconMuted,
        textColor: drift.textPrimary,
        tileColor: Colors.transparent,
        selectedTileColor: scheme.primary.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
      ),
      dividerTheme: DividerThemeData(color: drift.divider, thickness: 1, space: 1),
      popupMenuTheme: PopupMenuThemeData(
        color: drift.cardElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
        textStyle: bodyMd.copyWith(color: drift.textPrimary),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF243329) : const Color(0xFF1A2420),
          borderRadius: BorderRadius.circular(radiusSm),
          border: Border.all(color: drift.borderSubtle),
        ),
        textStyle: bodySm.copyWith(color: Colors.white),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return isDark ? drift.textMuted : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary.withValues(alpha: 0.45);
          }
          return drift.border;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(isDark ? drift.textInverse : Colors.white),
        side: BorderSide(color: drift.border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.all(scheme.primary),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.primary.withValues(alpha: isDark ? 0.24 : 0.14);
            }
            return drift.surfaceMuted;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return scheme.primary;
            return drift.textSecondary;
          }),
          side: WidgetStateProperty.all(BorderSide(color: drift.border)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? scheme.primary : primaryGreen,
          foregroundColor: isDark ? scheme.onPrimary : Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
          textStyle: labelLg,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: isDark ? scheme.onPrimary : Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.65), width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
          textStyle: labelLg,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: labelMd,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: drift.inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: drift.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: drift.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: scheme.error),
        ),
        labelStyle: bodyMd.copyWith(color: drift.textSecondary),
        hintStyle: bodyMd.copyWith(color: drift.textMuted),
        prefixIconColor: drift.iconMuted,
        suffixIconColor: drift.iconMuted,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: drift.surfaceMuted,
        selectedColor: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.14),
        disabledColor: drift.surfaceMuted.withValues(alpha: 0.5),
        labelStyle: bodySm.copyWith(
          fontWeight: FontWeight.w600,
          color: drift.textPrimary,
        ),
        secondaryLabelStyle: bodySm.copyWith(color: drift.textSecondary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusRound),
          side: BorderSide(color: drift.borderSubtle),
        ),
        side: BorderSide.none,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: isDark ? scheme.primary : primaryGreen,
        foregroundColor: isDark ? scheme.onPrimary : Colors.white,
        shape: const StadiumBorder(),
        elevation: isDark ? 2 : 4,
      ),
      cardTheme: CardThemeData(
        color: drift.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: drift.borderSubtle),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: drift.cardElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXl)),
        titleTextStyle: headingMd.copyWith(color: drift.textPrimary),
        contentTextStyle: bodyMd.copyWith(color: drift.textSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: drift.cardElevated,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: drift.cardElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
        ),
        dragHandleColor: drift.textMuted,
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF243329) : const Color(0xFF1A2420),
        contentTextStyle: bodyMd.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: drift.borderSubtle,
        circularTrackColor: drift.borderSubtle,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.error,
        textColor: Colors.white,
        textStyle: labelSm.copyWith(color: Colors.white, fontSize: 10),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(drift.surfaceMuted),
        dataRowColor: WidgetStateProperty.all(Colors.transparent),
        headingTextStyle: labelSm.copyWith(color: drift.textSecondary),
        dataTextStyle: bodySm.copyWith(color: drift.textPrimary),
        dividerThickness: 1,
        decoration: BoxDecoration(
          border: Border.all(color: drift.borderSubtle),
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(drift.textMuted.withValues(alpha: 0.45)),
        radius: const Radius.circular(radiusRound),
        thickness: WidgetStateProperty.all(6),
      ),
    );
  }
}
