import 'package:flutter/material.dart';

import 'access_keys.dart';
import 'user_access.dart';

/// Konfigurasjon for én fane i partner-detalj.
class PartnerDetailTabDef {
  final String accessKey;
  final IconData icon;
  final String label;

  const PartnerDetailTabDef({
    required this.accessKey,
    required this.icon,
    required this.label,
  });
}

/// Samarbeidspartner-tilganger (faner + modul).
class PartnerAccess {
  PartnerAccess._();

  static const detailTabs = <PartnerDetailTabDef>[
    PartnerDetailTabDef(
      accessKey: AccessKeys.partnersTabOversikt,
      icon: Icons.dashboard_outlined,
      label: 'Oversikt',
    ),
    PartnerDetailTabDef(
      accessKey: AccessKeys.partnersTabBilkontroll,
      icon: Icons.fact_check_outlined,
      label: 'Bilkontroll',
    ),
    PartnerDetailTabDef(
      accessKey: AccessKeys.partnersTabDokumenter,
      icon: Icons.folder_shared_outlined,
      label: 'Dokumenter',
    ),
    PartnerDetailTabDef(
      accessKey: AccessKeys.partnersTabLoyver,
      icon: Icons.verified_outlined,
      label: 'Løyver',
    ),
    PartnerDetailTabDef(
      accessKey: AccessKeys.partnersTabOppfolging,
      icon: Icons.track_changes_outlined,
      label: 'Oppfølging',
    ),
    PartnerDetailTabDef(
      accessKey: AccessKeys.partnersTabOppsummering,
      icon: Icons.summarize_outlined,
      label: 'Oppsummering',
    ),
    PartnerDetailTabDef(
      accessKey: AccessKeys.partnersTabFri,
      icon: Icons.beach_access_outlined,
      label: 'Fri',
    ),
  ];

  static List<PartnerDetailTabDef> visibleDetailTabs(UserAccess? access) {
    if (access == null) return const [];
    return detailTabs.where((t) => access.can(t.accessKey)).toList();
  }

  static bool canOpenPartnerDetail(UserAccess? access) =>
      visibleDetailTabs(access).isNotEmpty;

  static bool canOpenPartnersModule(UserAccess? access) {
    if (access == null) return false;
    return access.canPartnersTab ||
        access.canPartnersMenu ||
        access.canPartnersAdmin ||
        access.canFleetRoutes ||
        canOpenPartnerDetail(access);
  }
}
