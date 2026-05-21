import 'package:flutter/material.dart';

/// Status for rute-fordeling: kladd, registrert uten varsel, sendt med SMS.
abstract final class RouteDispatchStatus {
  static const staged = 'staged';
  static const registered = 'registered';
  static const sent = 'sent';

  static String shortLabel(String status) {
    switch (status) {
      case staged:
        return 'Kladd';
      case registered:
        return 'Uten varsel';
      case sent:
        return 'Varslet';
      default:
        return status;
    }
  }

  /// Bakgrunnsfarge i kalender-rute.
  static Color cellColor(String status) {
    switch (status) {
      case staged:
        return const Color(0xFFFF9800);
      case registered:
        return const Color(0xFF78909C);
      case sent:
        return const Color(0xFF2E7D32);
      default:
        return const Color(0xFF546E7A);
    }
  }

  static Color cellFill(String status, {required bool isDark}) {
    return cellColor(status).withValues(alpha: isDark ? 0.32 : 0.42);
  }

  static bool isVisibleInDriverPortal(String status) => status == sent;
}
