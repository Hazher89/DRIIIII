import 'package:flutter/material.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../partner_shell.dart';
import '../widgets/partner_modern_ui.dart';
import '../widgets/partner_ui.dart';
import 'owner_portal_common.dart';

class OwnerPortalOverviewPage extends StatefulWidget {
  final Partner partner;
  const OwnerPortalOverviewPage({super.key, required this.partner});

  @override
  State<OwnerPortalOverviewPage> createState() => _OwnerPortalOverviewPageState();
}

class _OwnerPortalOverviewPageState extends State<OwnerPortalOverviewPage> {
  OwnerPortalData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await OwnerPortalData.load(widget.partner);
    if (mounted) setState(() { _data = d; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.partner.name, style: const TextStyle(fontSize: 16)),
            const Text(
              kOwnerPortalBuildLabel,
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  PartnerHeroBanner(
                    title: 'Bil-eier oversikt',
                    subtitle: '${_data!.vehicles.length} kjøretøy · ${_data!.routes.length} ruter (90 d)',
                    leading: const Icon(Icons.business_center, color: Colors.white, size: 32),
                  ),
                  PartnerSmartActionsPanel(
                    title: 'Anbefalte handlinger',
                    actions: [
                      PartnerSmartAction(
                        label: 'Følg opp ${_data!.pendingAckTotal} ruter som venter svar',
                        hint: 'Gå til Alle ruter for å se status',
                        icon: Icons.route_outlined,
                      ),
                      const PartnerSmartAction(
                        label: 'Kontroller dokumenter og avtaler',
                        hint: 'Sikre at gyldige dokumenter er tilgjengelige',
                        icon: Icons.folder_open_outlined,
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GridView.count(
                      crossAxisCount: MediaQuery.sizeOf(context).width > 520 ? 3 : 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.15,
                      children: [
                        OwnerKpiCard(
                          label: 'Ruter i dag',
                          value: '${_data!.routesToday.length}',
                          icon: Icons.today,
                          accent: DriftProTheme.accentBlue,
                        ),
                        OwnerKpiCard(
                          label: 'Til godkjenning',
                          value: '${_data!.pendingAckTotal}',
                          icon: Icons.hourglass_top,
                          accent: _data!.pendingAckTotal > 0 ? Colors.orange : Colors.grey,
                        ),
                        OwnerKpiCard(
                          label: 'Utnyttelse 90d',
                          value: '${_data!.summary90.utilizationPercent.toStringAsFixed(0)}%',
                          icon: Icons.insights,
                        ),
                        OwnerKpiCard(
                          label: 'Jobbdager',
                          value: '${_data!.summary90.harRuteDays}',
                          icon: Icons.work_history,
                        ),
                        OwnerKpiCard(
                          label: 'Ledige dager',
                          value: '${_data!.summary90.ledigDays}',
                          icon: Icons.pause_circle_outline,
                          accent: Colors.orange,
                        ),
                        OwnerKpiCard(
                          label: 'Dokumenter',
                          value: '${_data!.documents.length}',
                          icon: Icons.folder_open,
                        ),
                      ],
                    ),
                  ),
                  const OwnerSectionTitle(
                    title: 'Dine biler — jobb vs. ledig',
                    subtitle: 'Stablet oversikt per MAVI-enhet (siste 90 dager)',
                  ),
                  ..._data!.vehicleStats.map((s) => OwnerVehicleStackCard(stats: s)),
                  const OwnerSectionTitle(title: 'Bedrift', subtitle: 'Kontakt og revisjon'),
                  _infoCard(context, widget.partner),
                  if (_data!.meetings.isNotEmpty) ...[
                    const OwnerSectionTitle(title: 'Neste møte'),
                    _meetingPreview(_data!.meetings.first),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      'Du forblir innlogget til du trykker «Logg ut». SMS ved nye ruter til sjåfører og deg som bil-eier.',
                      style: TextStyle(fontSize: 12, color: PartnerUi.mutedText(context), height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _infoCard(BuildContext context, Partner p) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _row(Icons.person_outline, 'Kontakt', p.ownerName ?? '—'),
            _row(Icons.phone_outlined, 'Telefon', p.phone ?? '—'),
            _row(Icons.email_outlined, 'E-post', p.email ?? '—'),
            _row(Icons.local_shipping_outlined, 'Kjøretøy registrert', '${p.vehicleCountRegistered}'),
            if (p.nextMeetingAt != null)
              _row(Icons.event_outlined, 'Neste møte', ownerFmtDateTime(p.nextMeetingAt!)),
            if (p.nextAuditAt != null)
              _row(Icons.fact_check_outlined, 'Neste revisjon', ownerFmtDate(p.nextAuditAt!)),
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

  Widget _meetingPreview(PartnerMeeting m) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListTile(
        leading: Icon(
          m.isAudit ? Icons.fact_check_outlined : Icons.event_outlined,
          color: DriftProTheme.primaryGreen,
        ),
        title: Text(m.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(ownerFmtDateTime(m.scheduledAt)),
      ),
    );
  }
}
