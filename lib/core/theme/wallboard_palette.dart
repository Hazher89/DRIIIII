import 'package:flutter/material.dart';

/// Dempede, moderne farger for infoskjerm /live.
abstract final class WallboardPalette {
  static const background = Color(0xFF13181F);
  static const card = Color(0xFF1C242E);
  static const cardInset = Color(0xFF171E27);
  static const border = Color(0xFF2E3A48);
  static const divider = Color(0xFF263040);

  static const headerStart = Color(0xFF3D5668);
  static const headerEnd = Color(0xFF2E4452);
  static const headerShadow = Color(0xFF4A6272);

  static const onJob = Color(0xFF6F9A82);
  static const vacationNow = Color(0xFFB8A87C);
  static const vacationSoon = Color(0xFF7F9DB8);
  static const birthdayToday = Color(0xFFC4A0AD);
  static const birthdaySoon = Color(0xFFA89CB8);

  static const transitMetro = Color(0xFFB88484);
  static const transitRail = Color(0xFF948EB8);
  static const transitTram = Color(0xFF82A89E);
  static const transitBus = Color(0xFF849AB8);

  static const weatherIcon = Color(0xFF92B4C8);
  static const nrkBadge = Color(0xFF9A8080);
  static const tickerBg = Color(0xFF10151B);
  static const tickerBorder = Color(0xFF242E3A);

  static const textPrimary = Color(0xFFE6EBF0);
  static const textSecondary = Color(0xFFA8B4C0);
  static const textMuted = Color(0xFF6E7C8A);

  static Color transitMode(String mode) {
    switch (mode) {
      case 'metro':
        return transitMetro;
      case 'tram':
        return transitTram;
      case 'rail':
        return transitRail;
      default:
        return transitBus;
    }
  }
}
