import 'package:flutter/material.dart';

import '../../../models/partner/partner.dart';
import '../widgets/partner_driver_deviations_panel.dart';
import '../widgets/partner_portal_page_shell.dart';

/// Bil-eier / partner: se rute-/kundeavvik fra egne sjåfører/ansatte.
class OwnerPortalDeviationsPage extends StatelessWidget {
  const OwnerPortalDeviationsPage({super.key, required this.partner});

  final Partner partner;

  @override
  Widget build(BuildContext context) {
    return PartnerPortalPageShell(
      title: 'Sjåføravvik',
      body: PartnerDriverDeviationsPanel(
        companyId: partner.companyId,
        partnerId: partner.id,
        title: 'Avvik i ditt firma',
        subtitle:
            'Alle avvik sendt av sjåfører og ansatte i ditt partnerfirma — '
            'aldri andre partnere. Viser også hvem som sendte.',
      ),
    );
  }
}
