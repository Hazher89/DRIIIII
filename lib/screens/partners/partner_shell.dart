import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/partner/partner_service.dart';
import '../../core/theme/app_theme.dart';
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
    final pages = [
      _PartnerOverviewPage(partner: p),
      _PartnerDocsPage(partner: p),
      _PartnerSummaryPage(partner: p),
      _PartnerRoutesPage(partner: p),
      _PartnerProfilePage(profile: widget.profile),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Oversikt'),
          NavigationDestination(icon: Icon(Icons.folder_open_outlined), selectedIcon: Icon(Icons.folder_open), label: 'Dokumenter'),
          NavigationDestination(
            icon: Icon(Icons.summarize_outlined),
            selectedIcon: Icon(Icons.summarize),
            label: 'Oppsumm.',
          ),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Ruter'),
          NavigationDestination(icon: Icon(Icons.person_outlined), selectedIcon: Icon(Icons.person), label: 'Profil'),
        ],
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
  const _PartnerRoutesPage({required this.partner});

  @override
  State<_PartnerRoutesPage> createState() => _PartnerRoutesPageState();
}

class _PartnerRoutesPageState extends State<_PartnerRoutesPage> {
  List<PartnerRouteShare> _routes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await PartnerService.fetchRouteShares(widget.partner.id);
    if (mounted) setState(() => _routes = r);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rute-PDF')),
      body: _routes.isEmpty
          ? const Center(child: Text('Ingen rutedeling registrert.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _routes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final r = _routes[i];
                return ListTile(
                  tileColor: Theme.of(context).brightness == Brightness.dark ? DriftProTheme.cardDark : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: Text(r.title ?? 'Rute'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r.shareDate.toString().split(' ').first}${r.isDailyShare ? ' · daglig rutine' : ''}'),
                      const SizedBox(height: 4),
                      Text(
                        _ackLabel(r),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _ackColor(r),
                        ),
                      ),
                    ],
                  ),
                  onTap: () => _openPdf(r),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'open') {
                        await _openPdf(r);
                      } else if (v == 'accept') {
                        await _setAck(r, true);
                      } else if (v == 'reject') {
                        await _setAck(r, false);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'open', child: Text('Åpne PDF')),
                      PopupMenuItem(value: 'accept', child: Text('Aksepter')),
                      PopupMenuItem(value: 'reject', child: Text('Ikke aksepter')),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _PartnerProfilePage extends StatelessWidget {
  final UserProfile profile;
  const _PartnerProfilePage({required this.profile});

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
            subtitle: const Text('Samarbeidspartner'),
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
