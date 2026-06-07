import 'package:flutter/material.dart';

/// Behandlingsstatus for risikoanalyser (ROS).
abstract final class RiskAssessmentStatuses {
  static const utkast = 'utkast';
  static const aktiv = 'aktiv';
  static const underBehandling = 'under_behandling';
  static const behandlet = 'behandlet';
  static const arkivert = 'arkivert';

  static const all = [
    utkast,
    aktiv,
    underBehandling,
    behandlet,
    arkivert,
  ];

  static String label(String status) {
    switch (status) {
      case utkast:
        return 'Utkast';
      case aktiv:
        return 'Ikke behandlet';
      case underBehandling:
        return 'Under behandling';
      case behandlet:
        return 'Behandlet';
      case arkivert:
        return 'Arkivert';
      default:
        return status;
    }
  }

  static Color chipColor(String status) {
    switch (status) {
      case behandlet:
        return const Color(0xFF2E7D32);
      case underBehandling:
        return const Color(0xFFF57C00);
      case arkivert:
        return const Color(0xFF757575);
      case utkast:
        return const Color(0xFF9E9E9E);
      default:
        return const Color(0xFFD32F2F);
    }
  }

  static bool isTreated(String status) => status == behandlet || status == arkivert;

  static bool isOpen(String status) =>
      status == aktiv || status == utkast || status == underBehandling;
}
