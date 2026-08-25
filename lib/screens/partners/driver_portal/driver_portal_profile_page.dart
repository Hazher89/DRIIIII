import 'package:flutter/material.dart';

import '../../../models/user_profile.dart';
import '../widgets/partner_portal_profile_page.dart';

/// Sjåfør-profil — Apple-klar (vilkår, personvern, support, slett konto).
class DriverPortalProfilePage extends StatelessWidget {
  final UserProfile profile;
  final String? partnerName;

  const DriverPortalProfilePage({
    super.key,
    required this.profile,
    this.partnerName,
  });

  @override
  Widget build(BuildContext context) {
    return PartnerPortalProfilePage(
      profile: profile,
      roleLabel: 'Sjåfør (MAVI-bil)',
      partnerName: partnerName,
    );
  }
}
