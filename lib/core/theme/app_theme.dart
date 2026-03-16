import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
  static const Color bgDark = Color(0xFF121212);

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
  static const Color absenceVacation = Color(0xFF42A5F5);
  static const Color absenceSickSelf = Color(0xFFEF5350);
  static const Color absenceSickChild = Color(0xFFFF7043);
  static const Color absenceLeave = Color(0xFF7E57C2);
  static const Color absenceSickNote = Color(0xFFE53935);

  // ── Neutral Colors ──
  static const Color surfaceLight = Color(0xFFF8FAF9);
  static const Color surfaceDark = Color(0xFF121A14);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF1A2A1D);
  static const Color dividerLight = Color(0xFFE0E8E2);
  static const Color dividerDark = Color(0xFF2A3A2D);

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

  // ── Shadows ──
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.04),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: primaryGreen.withOpacity(0.03),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get elevatedShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.08),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: primaryGreen.withOpacity(0.06),
      blurRadius: 32,
      offset: const Offset(0, 12),
    ),
  ];

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

  static TextStyle get caption => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: Colors.grey[500],
  );

  static TextStyle get statNumber => GoogleFonts.inter(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -1,
  );

  // ── Light Theme ──
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryGreen,
      brightness: Brightness.light,
      primary: primaryGreen,
      secondary: accentBlue,
      surface: surfaceLight,
      error: error,
    ),
    scaffoldBackgroundColor: surfaceLight,
    cardColor: cardLight,
    dividerColor: dividerLight,
    textTheme: GoogleFonts.interTextTheme(),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: headingMd.copyWith(color: primaryGreenDark),
      iconTheme: const IconThemeData(color: primaryGreenDark),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: labelLg,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryGreen,
        side: const BorderSide(color: primaryGreen, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: labelLg,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: primaryGreen, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: error),
      ),
      labelStyle: bodyMd.copyWith(color: Colors.grey[600]),
      hintStyle: bodyMd.copyWith(color: Colors.grey[400]),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusRound),
      ),
      side: BorderSide.none,
      labelStyle: bodySm.copyWith(fontWeight: FontWeight.w600),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: cardLight,
      selectedItemColor: primaryGreen,
      unselectedItemColor: Colors.grey[450],
      type: BottomNavigationBarType.fixed,
      elevation: 8,
      selectedLabelStyle: labelSm,
      unselectedLabelStyle: labelSm,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryGreen,
      foregroundColor: Colors.white,
      shape: StadiumBorder(),
      elevation: 4,
    ),
    cardTheme: CardThemeData(
      color: cardLight,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXl),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMd),
      ),
    ),
  );

  // ── Dark Theme ──
  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryGreen,
      brightness: Brightness.dark,
      primary: primaryGreenLight,
      secondary: accentBlueLight,
      surface: surfaceDark,
      error: error,
    ),
    scaffoldBackgroundColor: surfaceDark,
    cardColor: cardDark,
    dividerColor: dividerDark,
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: headingMd.copyWith(color: Colors.white),
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryGreenLight,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: labelLg,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryGreenLight,
        side: const BorderSide(color: primaryGreenLight, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: labelLg,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1F2D21),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: dividerDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: dividerDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: primaryGreenLight, width: 2),
      ),
      labelStyle: bodyMd.copyWith(color: Colors.grey[400]),
      hintStyle: bodyMd.copyWith(color: Colors.grey[600]),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: cardDark,
      selectedItemColor: primaryGreenLight,
      unselectedItemColor: Colors.grey[600],
      type: BottomNavigationBarType.fixed,
      elevation: 8,
      selectedLabelStyle: labelSm,
      unselectedLabelStyle: labelSm,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryGreenLight,
      foregroundColor: Colors.white,
      shape: StadiumBorder(),
      elevation: 4,
    ),
    cardTheme: CardThemeData(
      color: cardDark,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXl),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMd),
      ),
    ),
  );
}
