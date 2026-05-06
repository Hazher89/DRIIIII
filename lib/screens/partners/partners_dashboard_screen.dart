import 'package:flutter/material.dart';

import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import 'new_partner_screen.dart';
import 'partner_detail_screen.dart';

/// Oversikt over samarbeidspartnere (interne brukere).
class PartnersDashboardScreen extends StatefulWidget {
  const PartnersDashboardScreen({super.key});

  @override
  State<PartnersDashboardScreen> createState() => _PartnersDashboardScreenState();
}

class _PartnersDashboardScreenState extends State<PartnersDashboardScreen> {
  List<Partner> _partners = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) {
        setState(() {
          _loading = false;
          _error = 'Fant ikke bedrift for brukeren.';
        });
        return;
      }
      final list = await PartnerService.fetchPartners(companyId: cid);
      if (mounted) {
        setState(() {
          _partners = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openNew() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NewPartnerScreen()),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Samarbeidspartnere'),
        actions: [
          IconButton(
            tooltip: 'Ny samarbeidspartner',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _openNew,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNew,
        icon: const Icon(Icons.add),
        label: const Text('Registrer partner'),
        backgroundColor: DriftProTheme.primaryGreen,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(children: const [SizedBox(height: 120), Center(child: CircularProgressIndicator())])
            : _error != null
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    ],
                  )
                : _partners.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 80),
                          Icon(Icons.handshake_outlined, size: 56, color: Colors.grey),
                          SizedBox(height: 16),
                          Center(child: Text('Ingen samarbeidspartnere registrert ennå.')),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                        itemCount: _partners.length,
                        itemBuilder: (ctx, i) {
                          final p = _partners[i];
                          return _PartnerCard(
                            partner: p,
                            onTap: () async {
                              await Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) => PartnerDetailScreen(partner: p),
                                ),
                              );
                              _load();
                            },
                          );
                        },
                      ),
      ),
    );
  }
}

class _PartnerCard extends StatelessWidget {
  final Partner partner;
  final VoidCallback onTap;

  const _PartnerCard({required this.partner, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 0,
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.apartment_rounded, color: DriftProTheme.primaryGreen),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(partner.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        if (partner.orgNumber != null)
                          Text('Org.nr ${partner.orgNumber}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _mini(Icons.person_outline, partner.ownerName ?? 'Eier ikke registrert'),
                  _mini(Icons.phone_outlined, partner.phone ?? '—'),
                  _mini(Icons.email_outlined, partner.email ?? '—'),
                ],
              ),
              if (partner.nextMeetingAt != null || partner.nextAuditAt != null) ...[
                const Divider(height: 24),
                Wrap(
                  spacing: 12,
                  children: [
                    if (partner.nextMeetingAt != null)
                      Chip(
                        avatar: const Icon(Icons.event, size: 18),
                        label: Text('Møte ${_fmt(partner.nextMeetingAt!)}', style: const TextStyle(fontSize: 11)),
                      ),
                    if (partner.nextAuditAt != null)
                      Chip(
                        avatar: const Icon(Icons.fact_check, size: 18),
                        label: Text('Revisjon ${_date(partner.nextAuditAt!)}', style: const TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _mini(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey[800])),
        ),
      ],
    );
  }

  static String _fmt(DateTime d) => '${d.day}.${d.month}.${d.year}';
  static String _date(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
