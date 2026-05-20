import 'package:flutter/material.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/user_profile.dart';
import '../owner_portal/owner_portal_common.dart';
import '../partner_shell.dart';
import '../widgets/partner_ui.dart';
import 'driver_portal_common.dart';

class DriverPortalOverviewPage extends StatefulWidget {
  final Partner partner;
  final UserProfile profile;

  const DriverPortalOverviewPage({super.key, required this.partner, required this.profile});

  @override
  State<DriverPortalOverviewPage> createState() => _DriverPortalOverviewPageState();
}

class _DriverPortalOverviewPageState extends State<DriverPortalOverviewPage> {
  DriverPortalData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await DriverPortalData.load(
      partner: widget.partner,
      partnerVehicleId: widget.profile.partnerVehicleId,
    );
    if (mounted) setState(() { _data = d; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final v = _data?.vehicle;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.partner.name, style: const TextStyle(fontSize: 16)),
            const Text(
              kDriverPortalBuildLabel,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: DriftProTheme.accentBlue),
            ),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Oppdater', onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            tooltip: 'Logg ut',
            icon: const Icon(Icons.logout),
            onPressed: () => signOutFromPortal(context),
          ),
        ],
      ),
      body: _loading || _data == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  PartnerHeroBanner(
                    title: v != null
                        ? 'MAVI ${MaviUnitCodes.normalize(v.unitCode)}'
                        : 'Sjåfør-portal',
                    subtitle: v != null
                        ? '${v.registrationNumber}${v.driverName != null && v.driverName!.trim().isNotEmpty ? ' · ${v.driverName}' : ''}'
                        : 'Dine tildelte ruter',
                    leading: const Icon(Icons.local_shipping_outlined, color: Colors.white, size: 32),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.2,
                      children: [
                        OwnerKpiCard(
                          label: 'Ruter i dag',
                          value: '${_data!.routesToday.length}',
                          icon: Icons.today,
                          accent: DriftProTheme.accentBlue,
                        ),
                        OwnerKpiCard(
                          label: 'Til godkjenning',
                          value: '${_data!.pendingAck}',
                          icon: Icons.hourglass_top,
                          accent: _data!.pendingAck > 0 ? Colors.orange : Colors.grey,
                        ),
                        OwnerKpiCard(
                          label: 'Kommende',
                          value: '${_data!.routesUpcoming.length}',
                          icon: Icons.upcoming,
                        ),
                        OwnerKpiCard(
                          label: 'Arkiv',
                          value: '${_data!.routesArchive.length}',
                          icon: Icons.inventory_2_outlined,
                        ),
                      ],
                    ),
                  ),
                  if (_data!.pendingAck > 0) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Material(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        child: ListTile(
                          leading: const Icon(Icons.notifications_active, color: Colors.orange),
                          title: const Text(
                            'Du har ruter som venter på svar',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                          subtitle: Text(
                            'Gå til «Mine ruter» for PDF, starttid og godkjenning.',
                            style: TextStyle(fontSize: 12, color: PartnerUi.mutedText(context)),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const OwnerSectionTitle(
                    title: 'Bedrift',
                    subtitle: 'Kontakt MAVI / bil-eier',
                  ),
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _row(Icons.person_outline, 'Kontakt', widget.partner.ownerName ?? '—'),
                          _row(Icons.phone_outlined, 'Telefon', widget.partner.phone ?? '—'),
                          _row(Icons.email_outlined, 'E-post', widget.partner.email ?? '—'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Du forblir innlogget til du trykker «Logg ut». Du får SMS når MAVI publiserer nye ruter.',
                      style: TextStyle(fontSize: 12, color: PartnerUi.mutedText(context), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: DriftProTheme.primaryGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
                Text(value, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
