import 'package:flutter/material.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../widgets/partner_ui.dart';
import 'owner_portal_common.dart';

class OwnerPortalMeetingsPage extends StatefulWidget {
  final Partner partner;
  const OwnerPortalMeetingsPage({super.key, required this.partner});

  @override
  State<OwnerPortalMeetingsPage> createState() => _OwnerPortalMeetingsPageState();
}

class _OwnerPortalMeetingsPageState extends State<OwnerPortalMeetingsPage> {
  List<PartnerMeeting> _upcoming = [];
  List<PartnerMeeting> _past = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await OwnerPortalData.load(widget.partner);
    final now = DateTime.now();
    final up = d.meetings.where((m) => !m.scheduledAt.isBefore(now)).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final past = d.meetings.where((m) => m.scheduledAt.isBefore(now)).toList()
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    if (mounted) {
      setState(() {
        _upcoming = up;
        _past = past;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Møter & revisjon'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => signOutFromPortal(context)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  OwnerSectionTitle(title: 'Kommende (${_upcoming.length})'),
                  if (_upcoming.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Ingen planlagte møter.'),
                    )
                  else
                    ..._upcoming.map((m) => _tile(context, m, highlight: true)),
                  OwnerSectionTitle(title: 'Tidligere (${_past.length})'),
                  if (_past.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Ingen tidligere møter registrert.'),
                    )
                  else
                    ..._past.map((m) => _tile(context, m)),
                ],
              ),
            ),
    );
  }

  Widget _tile(BuildContext context, PartnerMeeting m, {bool highlight = false}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: highlight ? DriftProTheme.primaryGreen.withValues(alpha: 0.06) : null,
      child: ListTile(
        leading: Icon(
          m.isAudit ? Icons.fact_check_outlined : Icons.event_outlined,
          color: DriftProTheme.primaryGreen,
        ),
        title: Text(m.title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          '${PartnerMeeting.meetingTypeLabel(m.meetingType)}\n${ownerFmtDateTime(m.scheduledAt)}',
        ),
        isThreeLine: true,
        trailing: PartnerStatusBadge(
          label: PartnerMeeting.statusLabel(m.status),
          color: DriftProTheme.info,
        ),
      ),
    );
  }
}
