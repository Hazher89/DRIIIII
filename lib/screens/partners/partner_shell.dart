import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/session_sign_out.dart';
import '../../core/services/partner/mavi_unit_codes.dart';
import '../../core/services/partner/partner_portal_scope.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/fleet_shift.dart';
import '../../models/partner/partner.dart';
import '../../models/partner/partner_links.dart';
import '../../models/partner/vehicle_inspection.dart';
import '../../models/user_profile.dart';
import 'driver_portal/driver_portal_docs_page.dart';
import 'driver_portal/driver_portal_fri_page.dart';
import 'driver_portal/driver_portal_overview_page.dart';
import 'driver_portal/driver_portal_profile_page.dart';
import 'driver_portal/driver_portal_routes_page.dart';
import 'owner_portal/owner_portal_docs_page.dart';
import 'owner_portal/owner_portal_inspections_page.dart';
import 'owner_portal/owner_portal_meetings_page.dart';
import 'owner_portal/owner_portal_overview_page.dart';
import 'owner_portal/owner_portal_routes_page.dart';
import 'owner_portal/owner_portal_routes_focus.dart';
import 'owner_portal/owner_portal_vehicle_rental_page.dart';
import 'owner_portal/owner_portal_summary_page.dart';
import 'widgets/partner_portal_bottom_nav.dart';
import 'widgets/partner_route_pdf_actions.dart';
import 'widgets/partner_ui.dart' show PartnerStatusBadge;

DateTime _routeCalendarDay(PartnerRouteShare r) {
  final t = r.routeStartAt ?? r.shareDate;
  return DateTime(t.year, t.month, t.day);
}

bool _isActivePortalRoute(PartnerRouteShare r) {
  if (r.ackStatus == 'pending') return true;
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  return !_routeCalendarDay(r).isBefore(startOfToday.subtract(const Duration(days: 1)));
}

int _compareRoutesByStartDesc(PartnerRouteShare a, PartnerRouteShare b) {
  return _routeCalendarDay(b).compareTo(_routeCalendarDay(a));
}

List<Widget> _partnerLogoutActions(BuildContext context) => [
      IconButton(
        tooltip: 'Logg ut',
        icon: const Icon(Icons.logout),
        onPressed: () => signOutFromPortal(context),
      ),
    ];

/// Begrenset portal for [UserProfile] som er knyttet til en samarbeidspartner.
/// Versjonsmerke — synlig for bil-eier når ny portal er lastet.
const kOwnerPortalBuildLabel = 'Bil-eier v7';
const kDriverPortalBuildLabel = 'Sjåfør v5';

class PartnerShell extends StatefulWidget {
  final UserProfile profile;
  /// `owner` | `driver` fra [PartnerService.resolvePortalSession].
  final String? portalAccountKind;
  const PartnerShell({super.key, required this.profile, this.portalAccountKind});

  @override
  State<PartnerShell> createState() => _PartnerShellState();
}

class _PartnerShellState extends State<PartnerShell> {
  int _index = 0;
  Partner? _partner;
  bool _loading = true;
  OwnerPortalRoutesFocus? _routesFocus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pid = widget.profile.partnerId;
    if (pid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      await PartnerPortalScope.assertAccess(
        partnerId: pid,
        partnerVehicleId: widget.profile.partnerVehicleId,
      );
      final p = await PartnerService.fetchPartner(pid);
      if (!mounted) return;
      setState(() {
        _partner = p;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke åpne portal: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (widget.profile.partnerId == null || _partner == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Partner'),
          actions: _partnerLogoutActions(context),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange),
                const SizedBox(height: 16),
                const Text(
                  'Kontoen er ikke knyttet til en samarbeidspartner ennå.\n'
                  'Be MAVI om å opprette portal på nytt, eller prøv å koble kontoen på nytt.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () async {
                    setState(() => _loading = true);
                    await SupabaseService.ensureSessionLinkedToCompany();
                    final fresh = await SupabaseService.fetchCurrentUserProfile();
                    if (!mounted) return;
                    if (fresh?.partnerId != null) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(builder: (_) => PartnerShell(profile: fresh!)),
                      );
                      return;
                    }
                    setState(() => _loading = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Fant fortsatt ingen partner-kobling.')),
                    );
                  },
                  child: const Text('Koble konto på nytt'),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => signOutFromPortal(context),
                  child: const Text('Logg ut'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final p = _partner!;
    final isOwner = widget.portalAccountKind == 'owner' ||
        (widget.portalAccountKind == null && widget.profile.isPartnerPortalOwner);
    void goToRoutes({int tabIndex = 1, String? vehicleId}) {
      setState(() {
        _index = 3;
        _routesFocus = OwnerPortalRoutesFocus(tabIndex: tabIndex, vehicleId: vehicleId);
      });
    }

    final pages = isOwner
        ? [
            OwnerPortalOverviewPage(partner: p, onGoToRoutes: goToRoutes),
            OwnerPortalSummaryPage(partner: p),
            OwnerPortalDocsPage(partner: p),
            OwnerPortalRoutesPage(
              partner: p,
              launchFocus: _routesFocus,
              onLaunchFocusConsumed: () {
                if (_routesFocus != null) {
                  setState(() => _routesFocus = null);
                }
              },
            ),
            OwnerPortalVehicleRentalPage(partner: p),
            OwnerPortalMeetingsPage(partner: p),
            OwnerPortalInspectionsPage(partner: p),
            _PartnerProfilePage(profile: widget.profile, isOwner: true),
          ]
        : [
            DriverPortalOverviewPage(partner: p, profile: widget.profile),
            DriverPortalRoutesPage(partner: p, profile: widget.profile),
            DriverPortalDocsPage(partner: p),
            DriverPortalFriPage(partner: p, profile: widget.profile),
            DriverPortalProfilePage(profile: widget.profile),
          ];
    final ownerNavItems = const [
      PartnerPortalNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Oversikt'),
      PartnerPortalNavItem(icon: Icons.summarize_outlined, selectedIcon: Icons.summarize, label: 'Oppsummering'),
      PartnerPortalNavItem(icon: Icons.folder_open_outlined, selectedIcon: Icons.folder_open, label: 'Dokumenter'),
      PartnerPortalNavItem(icon: Icons.map_outlined, selectedIcon: Icons.map, label: 'Alle ruter'),
      PartnerPortalNavItem(icon: Icons.car_rental_outlined, selectedIcon: Icons.car_rental, label: 'Utleie'),
      PartnerPortalNavItem(icon: Icons.event_note_outlined, selectedIcon: Icons.event_note, label: 'Møter'),
      PartnerPortalNavItem(icon: Icons.fact_check_outlined, selectedIcon: Icons.fact_check, label: 'Bilkontroll'),
      PartnerPortalNavItem(icon: Icons.person_outlined, selectedIcon: Icons.person, label: 'Profil'),
    ];

    final driverDestinations = const [
      NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Oversikt'),
      NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Mine ruter'),
      NavigationDestination(icon: Icon(Icons.folder_open_outlined), selectedIcon: Icon(Icons.folder_open), label: 'Dokumenter'),
      NavigationDestination(icon: Icon(Icons.beach_access_outlined), selectedIcon: Icon(Icons.beach_access), label: 'Fri'),
      NavigationDestination(icon: Icon(Icons.person_outlined), selectedIcon: Icon(Icons.person), label: 'Profil'),
    ];

    final pageIndex = _index.clamp(0, pages.length - 1);
    final navIndex = _index.clamp(0, (isOwner ? ownerNavItems.length : driverDestinations.length) - 1);

    return Scaffold(
      // IndexedStack + nested Scaffold gir grå tom flate på Flutter web (Safari).
      body: pages[pageIndex],
      bottomNavigationBar: isOwner
          ? PartnerPortalBottomNav(
              selectedIndex: navIndex,
              onSelected: (i) => setState(() => _index = i),
              items: ownerNavItems,
            )
          : NavigationBar(
              selectedIndex: navIndex,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: driverDestinations,
            ),
    );
  }
}

class _PartnerOverviewPage extends StatelessWidget {
  final Partner partner;
  final bool isOwner;
  const _PartnerOverviewPage({required this.partner, this.isOwner = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(partner.name),
        actions: _partnerLogoutActions(context),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            isOwner ? 'Bil-eier portal — din bedrift' : 'Sjåfør-portal — dine tildelte ruter',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(partner.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          if (partner.orgNumber != null) Text('Org.nr ${partner.orgNumber}', style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          _infoTile(Icons.person_outline, 'Kontakt eier / leder', partner.ownerName ?? '—'),
          _infoTile(Icons.phone_outlined, 'Telefon', partner.phone ?? '—'),
          _infoTile(Icons.email_outlined, 'E-post', partner.email ?? '—'),
          _infoTile(Icons.place_outlined, 'Adresse', [
            partner.address,
            [partner.postalCode, partner.city].whereType<String>().where((e) => e.isNotEmpty).join(' '),
          ].whereType<String>().where((e) => e.isNotEmpty).join('\n').trim().isEmpty
              ? '—'
              : [
                  partner.address,
                  [partner.postalCode, partner.city].whereType<String>().where((e) => e.isNotEmpty).join(' '),
                ].whereType<String>().where((e) => e.isNotEmpty).join('\n')),
          const Divider(height: 32),
          _infoTile(Icons.local_shipping_outlined, 'Registrerte kjøretøy (bedrift)', '${partner.vehicleCountRegistered}'),
          _infoTile(Icons.scale_outlined, 'Nyttelast (kg, oppgitt)', partner.vehicleMaxPayloadKg?.toString() ?? '—'),
          _infoTile(Icons.verified_outlined, 'EU-godkjent (oppgitt)', partner.euApproved == null ? '—' : (partner.euApproved! ? 'Ja' : 'Nei')),
          const Divider(height: 32),
          _infoTile(Icons.event_outlined, 'Neste planlagte møte', partner.nextMeetingAt != null ? _fmt(partner.nextMeetingAt!) : '—'),
          _infoTile(Icons.fact_check_outlined, 'Siste revisjon / audit', partner.lastAuditAt != null ? _dateOnly(partner.lastAuditAt!) : '—'),
          _infoTile(Icons.schedule_outlined, 'Neste revisjon / audit', partner.nextAuditAt != null ? _dateOnly(partner.nextAuditAt!) : '—'),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) => '${d.day}.${d.month}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  static String _dateOnly(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _infoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: DriftProTheme.primaryGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
                Text(value, style: const TextStyle(fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerDocsPage extends StatefulWidget {
  final Partner partner;
  final bool isOwner;
  const _PartnerDocsPage({required this.partner, this.isOwner = true});

  @override
  State<_PartnerDocsPage> createState() => _PartnerDocsPageState();
}

class _PartnerDocsPageState extends State<_PartnerDocsPage> {
  List<PartnerDocument> _docs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = widget.isOwner
        ? await PartnerService.fetchOwnerPortalDocuments(widget.partner.id)
        : await PartnerService.fetchDriverPortalDocuments(widget.partner.id);
    if (mounted) setState(() => _docs = d);
  }

  Future<void> _open(PartnerDocument doc) async {
    final p = doc.storagePath;
    if (p == null || p.isEmpty) return;
    try {
      final url = await PartnerService.getDocumentPdfSignedUrl(p);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunne ikke åpne: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isOwner ? 'Dokumenter (bedrift)' : 'Dokumenter (sjåfør)'),
        actions: _partnerLogoutActions(context),
      ),
      body: _docs.isEmpty
          ? Center(
              child: Text(
                widget.isOwner
                    ? 'Ingen dokumenter delt med bil-eier ennå.'
                    : 'Ingen dokumenter delt med sjåfør ennå.',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final doc = _docs[i];
                return ListTile(
                  tileColor: Theme.of(context).brightness == Brightness.dark ? DriftProTheme.cardDark : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: const Icon(Icons.description_outlined),
                  title: Text(doc.title),
                  subtitle: Text(
                    '${PartnerDocument.documentTypeLabel(doc.documentType)} · '
                    '${doc.fileName ?? doc.storagePath ?? ''}',
                  ),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _open(doc),
                );
              },
            ),
    );
  }
}

class _PartnerRoutesPage extends StatefulWidget {
  final Partner partner;
  final UserProfile profile;
  final bool isOwner;
  const _PartnerRoutesPage({
    required this.partner,
    required this.profile,
    this.isOwner = false,
  });

  @override
  State<_PartnerRoutesPage> createState() => _PartnerRoutesPageState();
}

class _PartnerRoutesPageState extends State<_PartnerRoutesPage> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<PartnerRouteShare> _active = [];
  List<PartnerRouteShare> _history = [];
  Map<String, FleetShiftDefinition> _shifts = {};
  Map<String, PartnerVehicle> _vehiclesById = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final vid = widget.isOwner ? null : widget.profile.partnerVehicleId;
    final all = (!widget.isOwner && widget.partner.routesOwnerOnly)
        ? <PartnerRouteShare>[]
        : await PartnerService.fetchRouteShares(
            widget.partner.id,
            partnerVehicleId: vid,
            sentOnly: true,
          );
    final cid = widget.partner.companyId;
    final shifts = await PartnerService.fetchFleetShifts(cid);
    final shiftMap = {for (final s in shifts) s.id: s};
    Map<String, PartnerVehicle> vehicleMap = {};
    if (widget.isOwner) {
      final vehicles = await PartnerService.fetchVehicles(widget.partner.id);
      vehicleMap = {for (final v in vehicles) v.id: v};
    }
    final active = all.where(_isActivePortalRoute).toList()..sort(_compareRoutesByStartDesc);
    final history = all.where((r) => !_isActivePortalRoute(r)).toList()..sort(_compareRoutesByStartDesc);
    if (mounted) {
      setState(() {
        _active = active;
        _history = history;
        _shifts = shiftMap;
        _vehiclesById = vehicleMap;
        _loading = false;
      });
    }
  }

  String _shiftLabel(PartnerRouteShare r) {
    final id = r.shiftId;
    if (id == null) return '';
    return _shifts[id]?.name ?? '';
  }

  String _startLabel(PartnerRouteShare r) {
    if (r.routeStartAt == null) return '';
    final t = r.routeStartAt!.toLocal();
    return 'Start ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openPdf(PartnerRouteShare r) async {
    await PartnerRoutePdfActions.openPdf(context, r);
  }

  Future<void> _setAck(PartnerRouteShare r, bool accepted) async {
    final noteCtrl = TextEditingController();
    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(accepted ? 'Aksepter rute' : 'Avlys rute'),
        content: TextField(
          controller: noteCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: accepted ? 'Kommentar (valgfritt)' : 'Begrunnelse til MAVI *',
            hintText: accepted ? null : 'F.eks. bil i verksted, sykdom …',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(accepted ? 'Aksepter' : 'Send avlysning')),
        ],
      ),
    );
    if (shouldContinue != true) {
      noteCtrl.dispose();
      return;
    }
    final comment = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (!accepted && comment.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Skriv en begrunnelse når du avlyser ruten.')),
        );
      }
      return;
    }
    try {
      await PartnerService.updateRouteAcknowledgement(
        routeShareId: r.id,
        accepted: accepted,
        comment: comment.isEmpty ? null : comment,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accepted
                  ? 'Ruten er akseptert.'
                  : 'Ruten er avlyst. Begrunnelsen er sendt til MAVI.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke lagre: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    await _load();
  }

  String _ackLabel(PartnerRouteShare r) {
    switch (r.ackStatus) {
      case 'accepted':
        return 'Akseptert';
      case 'rejected':
        return 'Ikke akseptert';
      default:
        return 'Venter svar';
    }
  }

  Color _ackColor(PartnerRouteShare r) {
    switch (r.ackStatus) {
      case 'accepted':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Widget _routeTile(PartnerRouteShare r, {bool showActions = true}) {
    final shift = _shiftLabel(r);
    final start = _startLabel(r);
    final vehicle = r.partnerVehicleId != null ? _vehiclesById[r.partnerVehicleId] : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PartnerRoutePdfActions.ackDot(r, size: 12),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(r.title ?? 'Rute', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                Text(
                  _ackLabel(r),
                  style: TextStyle(fontWeight: FontWeight.w700, color: _ackColor(r), fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (vehicle != null)
              Text(
                'MAVI ${MaviUnitCodes.normalize(vehicle.unitCode)}',
                style: const TextStyle(fontWeight: FontWeight.w800, color: DriftProTheme.primaryGreen),
              ),
            Text(
              'Rutedag: ${DateFormat('EEEE d. MMM yyyy', 'nb').format(_routeCalendarDay(r))}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (shift.isNotEmpty) Text('Skift: $shift'),
            if (start.isNotEmpty)
              Text(
                start,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: DriftProTheme.accentBlue),
              ),
            if ((r.notes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Melding fra MAVI: ${r.notes}', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
            ],
            if ((r.ackComment ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Din tilbakemelding: ${r.ackComment}',
                style: TextStyle(color: Colors.grey.shade800, fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openPdf(r),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Vis rute-PDF'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _openPdf(r),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Last ned'),
                ),
              ],
            ),
            if (showActions && r.ackStatus == 'pending') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _setAck(r, true),
                      style: FilledButton.styleFrom(backgroundColor: Colors.green),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Aksepter rute'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _setAck(r, false),
                    icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                    label: const Text('Avlys'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isOwner ? 'Alle ruter' : 'Mine ruter'),
        actions: _partnerLogoutActions(context),
        bottom: TabBar(
          controller: _tab,
          tabs: [
            Tab(text: 'Aktive (${_active.length})'),
            Tab(text: 'Historikk (${_history.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: TabBarView(
                controller: _tab,
                children: [
                  _active.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Text(
                                'Ingen aktive ruter.\nDu får SMS når MAVI tildeler en ny rute.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _active.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _routeTile(_active[i]),
                        ),
                  _history.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Center(child: Text('Ingen tidligere ruter.')),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _history.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _routeTile(_history[i], showActions: false),
                        ),
                ],
              ),
            ),
    );
  }
}

class _PartnerMeetingsPage extends StatefulWidget {
  final Partner partner;
  const _PartnerMeetingsPage({required this.partner});

  @override
  State<_PartnerMeetingsPage> createState() => _PartnerMeetingsPageState();
}

class _PartnerMeetingsPageState extends State<_PartnerMeetingsPage> {
  List<PartnerMeeting> _meetings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await PartnerService.fetchPortalMeetings(widget.partner.id);
    if (mounted) {
      setState(() {
        _meetings = m.where((x) => !x.isArchived).toList();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Møter & audit'),
        actions: _partnerLogoutActions(context),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _meetings.isEmpty
              ? const Center(child: Text('Ingen planlagte møter.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _meetings.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final m = _meetings[i];
                    return ListTile(
                      tileColor: Theme.of(context).brightness == Brightness.dark
                          ? DriftProTheme.cardDark
                          : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      leading: Icon(
                        m.isAudit ? Icons.fact_check_outlined : Icons.event_outlined,
                        color: DriftProTheme.primaryGreen,
                      ),
                      title: Text(m.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${PartnerMeeting.meetingTypeLabel(m.meetingType)}\n'
                        '${DateFormat('d. MMM yyyy HH:mm', 'nb').format(m.scheduledAt.toLocal())}',
                      ),
                      isThreeLine: true,
                      trailing: PartnerStatusBadge(
                        label: PartnerMeeting.statusLabel(m.status),
                        color: DriftProTheme.info,
                      ),
                    );
                  },
                ),
    );
  }
}

class _PartnerInspectionsPage extends StatefulWidget {
  final Partner partner;
  const _PartnerInspectionsPage({required this.partner});

  @override
  State<_PartnerInspectionsPage> createState() => _PartnerInspectionsPageState();
}

class _PartnerInspectionsPageState extends State<_PartnerInspectionsPage> {
  List<PartnerVehicleInspection> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await PartnerService.fetchVehicleInspections(widget.partner.id);
    if (mounted) {
      setState(() {
        _items = list.take(30).toList();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bilkontroll'),
        actions: _partnerLogoutActions(context),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('Ingen registrerte bilkontroller ennå.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final ins = _items[i];
                    final label = ins.registrationNumber ?? ins.unitCode ?? 'Bil';
                    return ListTile(
                      tileColor: Theme.of(context).brightness == Brightness.dark
                          ? DriftProTheme.cardDark
                          : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      leading: Icon(
                        ins.hasDeviation ? Icons.warning_amber : Icons.check_circle,
                        color: ins.hasDeviation ? Colors.orange : Colors.green,
                      ),
                      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${DateFormat('d. MMM yyyy', 'nb').format(ins.inspectedAt.toLocal())}\n'
                        '${ins.hasDeviation ? (ins.deviationNotes ?? "Avvik registrert") : "OK — ingen avvik"}',
                      ),
                      isThreeLine: true,
                    );
                  },
                ),
    );
  }
}

class _PartnerFriPage extends StatefulWidget {
  final Partner partner;
  final UserProfile profile;
  const _PartnerFriPage({required this.partner, required this.profile});

  @override
  State<_PartnerFriPage> createState() => _PartnerFriPageState();
}

class _PartnerFriPageState extends State<_PartnerFriPage> {
  List<PartnerFriRequest> _mine = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await PartnerService.fetchFriRequests(partnerId: widget.partner.id);
    final vid = widget.profile.partnerVehicleId;
    if (mounted) {
      setState(() {
        _mine = vid == null ? all : all.where((r) => r.partnerVehicleId == vid).toList();
        _loading = false;
      });
    }
  }

  Future<void> _requestFri() async {
    final reasonCtrl = TextEditingController();
    var date = DateTime.now().add(const Duration(days: 1));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Søk fri'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Dato'),
                subtitle: Text(DateFormat('d. MMM yyyy', 'nb').format(date)),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) setLocal(() => date = d);
                },
              ),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Begrunnelse',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final cid = widget.partner.companyId;
    await PartnerService.createFriRequest(
      companyId: cid,
      partnerId: widget.partner.id,
      partnerVehicleId: widget.profile.partnerVehicleId,
      requestDate: date,
      reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fri-forespørsel sendt. Venter godkjenning fra MAVI.')),
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fri'),
        actions: [
          IconButton(
            tooltip: 'Søk fri',
            onPressed: _requestFri,
            icon: const Icon(Icons.add),
          ),
          ..._partnerLogoutActions(context),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _mine.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Ingen fri-forespørsler ennå.'),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _requestFri,
                        icon: const Icon(Icons.beach_access),
                        label: const Text('Søk fri'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _mine.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final r = _mine[i];
                    Color c = Colors.orange;
                    if (r.status == 'approved') c = Colors.green;
                    if (r.status == 'rejected') c = Colors.red;
                    return ListTile(
                      tileColor: Theme.of(context).brightness == Brightness.dark
                          ? DriftProTheme.cardDark
                          : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      title: Text(DateFormat('d. MMM yyyy', 'nb').format(r.requestDate)),
                      subtitle: Text(r.reason ?? '—'),
                      trailing: Text(r.status, style: TextStyle(color: c, fontWeight: FontWeight.w700)),
                    );
                  },
                ),
    );
  }
}

class _PartnerProfilePage extends StatelessWidget {
  final UserProfile profile;
  final bool isOwner;
  const _PartnerProfilePage({required this.profile, this.isOwner = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        actions: _partnerLogoutActions(context),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.2),
            child: Text(profile.initials, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          Text(profile.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(profile.email, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Rolle'),
            subtitle: Text(isOwner ? 'Bil-eier (hele bedriften)' : 'Sjåfør (MAVI-bil)'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => signOutFromPortal(context),
            icon: const Icon(Icons.logout),
            label: const Text('Logg ut'),
          ),
        ],
      ),
    );
  }
}
