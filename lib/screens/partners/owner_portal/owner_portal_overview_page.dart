import 'package:flutter/material.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/services/partner/partner_deduction_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../widgets/partner_portal_page_shell.dart';
import '../widgets/partner_modern_ui.dart';
import '../widgets/partner_portal_route_detail_page.dart';
import '../widgets/partner_ui.dart';
import '../widgets/eco_driving_badge.dart';
import 'owner_portal_common.dart';
import '../../../widgets/auth_legal_links.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import '../../more/driftpro_platform_catalog.dart';
import '../../profile/delete_own_account_dialog.dart';

class OwnerPortalOverviewPage extends StatefulWidget {
  final Partner partner;
  final void Function({int tabIndex, String? vehicleId})? onGoToRoutes;
  final VoidCallback? onGoToTrekk;

  const OwnerPortalOverviewPage({
    super.key,
    required this.partner,
    this.onGoToRoutes,
    this.onGoToTrekk,
  });

  @override
  State<OwnerPortalOverviewPage> createState() => _OwnerPortalOverviewPageState();
}

class _OwnerPortalOverviewPageState extends State<OwnerPortalOverviewPage> {
  OwnerPortalData? _data;
  int _trekkCount = 0;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final d = await OwnerPortalData.load(widget.partner);
      final trekk = await PartnerDeductionService.listCasesPortal(partnerId: widget.partner.id);
      if (!mounted) return;
      setState(() {
        _data = d;
        _trekkCount = trekk.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PartnerPortalPageShell(
      title: widget.partner.name,
      actions: [
        IconButton(tooltip: 'Oppdater', onPressed: _load, icon: const Icon(Icons.refresh)),
        IconButton(
          tooltip: 'Logg ut',
          icon: const Icon(Icons.logout),
          onPressed: () => signOutFromPortal(context),
        ),
      ],
      body: _loading
          ? const DriftProLoadingCenter()
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.orange),
                        const SizedBox(height: 12),
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Prøv igjen'),
                        ),
                      ],
                    ),
                  ),
                )
              : _data == null
                  ? const Center(child: Text('Ingen data'))
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: EcoDrivingBadge.forPartner(
                      widget.partner,
                      prominent: true,
                    ),
                  ),
                  if (_data!.pendingAckTotal > 0) ...[
                    _pendingRoutesBanner(context, onTap: _openPendingRoutes),
                    const SizedBox(height: 12),
                  ],
                  PartnerSmartActionsPanel(
                    title: 'Anbefalte handlinger',
                    actions: [
                      if (_data!.pendingAckTotal > 0)
                        PartnerSmartAction(
                          label: '${_data!.pendingAckTotal} rute(r) venter på aksept',
                          hint: 'Åpner Kommende — vis PDF og aksepter',
                          icon: Icons.check_circle_outline,
                          onTap: _openPendingRoutes,
                        ),
                      PartnerSmartAction(
                        label: 'Tidligere ruter med PDF og kunder',
                        hint: 'Alle ruter → Tidligere — filtrer dag/uke/mnd/år og per bil',
                        icon: Icons.history_edu_outlined,
                      ),
                      const PartnerSmartAction(
                        label: 'Se siste økonomiske oppsummering',
                        hint: 'Fanen «Oppsummering» — beløp, arkiv og total per måned',
                        icon: Icons.summarize_outlined,
                      ),
                      const PartnerSmartAction(
                        label: 'Kontroller dokumenter og avtaler',
                        hint: 'Avtaler og andre filer under «Dokumenter»',
                        icon: Icons.folder_open_outlined,
                      ),
                      if (_trekkCount > 0)
                        PartnerSmartAction(
                          label: 'Se $_trekkCount trekk i arkivet',
                          hint: 'Fanen «Trekk» — saksnummer, begrunnelse og bevis',
                          icon: Icons.gavel_rounded,
                          onTap: widget.onGoToTrekk,
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GridView.count(
                      crossAxisCount: MediaQuery.sizeOf(context).width > 520 ? 3 : 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: MediaQuery.sizeOf(context).width > 520 ? 2.4 : 2.55,
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
                        OwnerKpiCard(
                          label: 'Trekk',
                          value: '$_trekkCount',
                          icon: Icons.gavel_rounded,
                          accent: _trekkCount > 0 ? const Color(0xFF9A3412) : Colors.grey,
                          onTap: widget.onGoToTrekk,
                        ),
                      ],
                    ),
                  ),
                  const OwnerSectionTitle(
                    title: 'Dine biler — jobb vs. ledig',
                    subtitle: 'Stablet oversikt per MAVI-enhet (siste 90 dager)',
                  ),
                  ..._data!.vehicleStats.map(
                    (s) => OwnerVehicleStackCard(
                      stats: s,
                      onTap: widget.onGoToRoutes == null
                          ? null
                          : () => widget.onGoToRoutes!(
                                tabIndex: 1,
                                vehicleId: s.vehicle.id,
                              ),
                    ),
                  ),
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
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: AuthLegalLinks(compact: true),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: DriftProTheme.error.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: DriftProTheme.error.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Slett konto',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: DriftProTheme.error,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'DriftPro er kun for ${DriftProPlatformCatalog.companyName}. '
                            'Slett innlogging og personopplysninger her.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: PartnerUi.mutedText(context),
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () => showDeleteOwnAccountDialog(context),
                            icon: const Icon(Icons.delete_forever_outlined, size: 18),
                            label: const Text('Slett konto permanent'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: DriftProTheme.error,
                              side: const BorderSide(color: DriftProTheme.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  void _openPendingRoutes() {
    final newest = _data?.newestPendingAckRoute;
    if (newest != null && _data != null) {
      PartnerPortalRouteDetailPage.open(
        context,
        route: newest,
        shifts: _data!.shiftsById,
        onReload: _load,
        onBehalfOfDriver: true,
      );
      return;
    }
    widget.onGoToRoutes?.call(tabIndex: 1);
  }

  Widget _pendingRoutesBanner(BuildContext context, {VoidCallback? onTap}) {
    final n = _data!.pendingAckTotal;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.notifications_active, color: Colors.orange.shade800, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$n NYE RUTER — TRYKK HER',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: Colors.orange.shade900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      onTap != null
                          ? 'Trykk her for Kommende.\n1. Åpne rute-PDF\n2. Trykk «Aksepter rute»'
                          : '1. Gå til «Alle ruter» → Kommende\n2. Åpne rute-PDF\n3. Trykk «Aksepter rute»',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: Colors.orange.shade900.withValues(alpha: 0.9),
                      ),
                    ),
                    if (onTap != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Gå til Kommende →',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _infoCard(BuildContext context, Partner p) {
    final ecoLabel = switch (p.ecoDrivingStatus) {
      EcoDrivingStatus.completed => p.ecoDrivingCompletedAt != null
          ? 'Gjennomført ${ownerFmtDate(p.ecoDrivingCompletedAt!)}'
          : 'Gjennomført',
      EcoDrivingStatus.overdue => p.ecoDrivingDeadline != null
          ? 'Frist utløpt ${ownerFmtDate(p.ecoDrivingDeadline!)}'
          : 'Frist utløpt',
      EcoDrivingStatus.required => p.ecoDrivingDeadline != null
          ? 'Skal tas innen ${ownerFmtDate(p.ecoDrivingDeadline!)}'
          : 'Skal tas innen 3 måneder',
    };
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
            _row(Icons.eco_rounded, 'ECO Driving Kurs', ecoLabel),
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
