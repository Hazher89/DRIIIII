import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/partner/partner_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/fleet_shift.dart';
import '../../models/partner/partner.dart';
import '../../models/partner/partner_links.dart';
import '../../models/user_profile.dart';

/// Begrenset portal for [UserProfile] som er knyttet til en samarbeidspartner.
class PartnerShell extends StatefulWidget {
  final UserProfile profile;
  const PartnerShell({super.key, required this.profile});

  @override
  State<PartnerShell> createState() => _PartnerShellState();
}

class _PartnerShellState extends State<PartnerShell> {
  int _index = 0;
  Partner? _partner;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pid = widget.profile.partnerId;
    if (pid == null) {
      setState(() => _loading = false);
      return;
    }
    final p = await PartnerService.fetchPartner(pid);
    if (mounted) {
      setState(() {
        _partner = p;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (widget.profile.partnerId == null || _partner == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Partner')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange),
                const SizedBox(height: 16),
                const Text(
                  'Kontoen er ikke knyttet til en samarbeidspartner ennå.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Supabase.instance.client.auth.signOut(),
                  child: const Text('Logg ut'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final p = _partner!;
    final isOwner = widget.profile.partnerVehicleId == null;
    final pages = [
      _PartnerOverviewPage(partner: p),
      _PartnerDocsPage(partner: p),
      _PartnerSummaryPage(partner: p),
      _PartnerRoutesPage(partner: p, profile: widget.profile, isOwner: isOwner),
      if (!isOwner) _PartnerFriPage(partner: p, profile: widget.profile),
      _PartnerProfilePage(profile: widget.profile, isOwner: isOwner),
    ];
    final destinations = [
      const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Oversikt'),
      const NavigationDestination(icon: Icon(Icons.folder_open_outlined), selectedIcon: Icon(Icons.folder_open), label: 'Dokumenter'),
      const NavigationDestination(
        icon: Icon(Icons.summarize_outlined),
        selectedIcon: Icon(Icons.summarize),
        label: 'Oppsumm.',
      ),
      NavigationDestination(
        icon: const Icon(Icons.map_outlined),
        selectedIcon: const Icon(Icons.map),
        label: isOwner ? 'Alle ruter' : 'Mine ruter',
      ),
      if (!isOwner)
        const NavigationDestination(
          icon: Icon(Icons.beach_access_outlined),
          selectedIcon: Icon(Icons.beach_access),
          label: 'Fri',
        ),
      const NavigationDestination(icon: Icon(Icons.person_outlined), selectedIcon: Icon(Icons.person), label: 'Profil'),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index.clamp(0, destinations.length - 1),
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: destinations,
      ),
    );
  }
}

class _PartnerOverviewPage extends StatelessWidget {
  final Partner partner;
  const _PartnerOverviewPage({required this.partner});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text(partner.name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Leverandør / samarbeidspartner',
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
  const _PartnerDocsPage({required this.partner});

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
    final d = await PartnerService.fetchDocuments(
      widget.partner.id,
      docCategories: const ['general', 'agreement'],
    );
    if (mounted) setState(() => _docs = d);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delte dokumenter')),
      body: _docs.isEmpty
          ? const Center(child: Text('Ingen dokumenter delt ennå.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final doc = _docs[i];
                return ListTile(
                  tileColor: Theme.of(context).brightness == Brightness.dark ? DriftProTheme.cardDark : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: const Icon(Icons.description_outlined),
                  title: Text(doc.title),
                  subtitle: Text(doc.fileName ?? doc.storagePath ?? ''),
                );
              },
            ),
    );
  }
}

class _PartnerSummaryPage extends StatefulWidget {
  final Partner partner;
  const _PartnerSummaryPage({required this.partner});

  @override
  State<_PartnerSummaryPage> createState() => _PartnerSummaryPageState();
}

class _PartnerSummaryPageState extends State<_PartnerSummaryPage> {
  List<PartnerDocument> _docs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await PartnerService.fetchDocuments(
      widget.partner.id,
      docCategories: const ['summary'],
    );
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunne ikke åpne PDF: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Oppsummering')),
      body: _docs.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Ingen oppsummering er delt med dere ennå.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final doc = _docs[i];
                return ListTile(
                  tileColor: Theme.of(context).brightness == Brightness.dark ? DriftProTheme.cardDark : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: Text(doc.title),
                  subtitle: Text(doc.fileName ?? ''),
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
    final all = await PartnerService.fetchRouteShares(
      widget.partner.id,
      partnerVehicleId: vid,
      sentOnly: true,
    );
    final cid = widget.partner.companyId;
    final shifts = await PartnerService.fetchFleetShifts(cid);
    final shiftMap = {for (final s in shifts) s.id: s};
    final now = DateTime.now();
    final active = all.where((r) {
      if (r.ackStatus == 'pending') return true;
      final d = DateTime(r.shareDate.year, r.shareDate.month, r.shareDate.day);
      return !d.isBefore(DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1)));
    }).toList();
    final history = all.where((r) => !active.contains(r)).toList();
    if (mounted) {
      setState(() {
        _active = active;
        _history = history;
        _shifts = shiftMap;
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
    try {
      final url = await PartnerService.getRoutePdfSignedUrl(r.pdfStoragePath);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunne ikke åpne PDF: $e')));
    }
  }

  Future<void> _setAck(PartnerRouteShare r, bool accepted) async {
    final noteCtrl = TextEditingController();
    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(accepted ? 'Aksepter rute' : 'Avvis rute'),
        content: TextField(
          controller: noteCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Kommentar (valgfritt)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lagre')),
        ],
      ),
    );
    if (shouldContinue != true) return;
    await PartnerService.updateRouteAcknowledgement(
      routeShareId: r.id,
      accepted: accepted,
      comment: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
    );
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
    return ListTile(
      tileColor: Theme.of(context).brightness == Brightness.dark ? DriftProTheme.cardDark : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: const Icon(Icons.picture_as_pdf_outlined),
      title: Text(r.title ?? 'Rute'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(DateFormat('d. MMM yyyy', 'nb').format(r.shareDate)),
          if (shift.isNotEmpty) Text('Skift: $shift', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (start.isNotEmpty) Text(start),
          const SizedBox(height: 4),
          Text(
            _ackLabel(r),
            style: TextStyle(fontWeight: FontWeight.w700, color: _ackColor(r)),
          ),
        ],
      ),
      onTap: () => _openPdf(r),
      trailing: showActions && r.ackStatus == 'pending'
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Aksepter — skal kjøre',
                  icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                  onPressed: () => _setAck(r, true),
                ),
                IconButton(
                  tooltip: 'Avvis',
                  icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                  onPressed: () => _setAck(r, false),
                ),
              ],
            )
          : IconButton(icon: const Icon(Icons.open_in_new), onPressed: () => _openPdf(r)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isOwner ? 'Alle ruter' : 'Mine ruter'),
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
          : TabBarView(
              controller: _tab,
              children: [
                _active.isEmpty
                    ? const Center(
                        child: Text(
                          'Ingen nye ruter. Du får SMS når noe er tildelt.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _active.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _routeTile(_active[i]),
                      ),
                _history.isEmpty
                    ? const Center(child: Text('Ingen tidligere ruter.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _history.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _routeTile(_history[i], showActions: false),
                      ),
              ],
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
      appBar: AppBar(title: const Text('Profil')),
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
            onPressed: () => Supabase.instance.client.auth.signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Logg ut'),
          ),
        ],
      ),
    );
  }
}
