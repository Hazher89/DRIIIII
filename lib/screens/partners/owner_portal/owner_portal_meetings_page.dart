import 'package:flutter/material.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../widgets/partner_portal_page_shell.dart';
import '../widgets/partner_ui.dart';
import 'owner_portal_common.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

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
    final muted = PartnerUi.mutedText(context);
    return PartnerPortalPageShell(
      title: 'Møter & revisjon',
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () => signOutFromPortal(context),
        ),
      ],
      body: _loading
          ? const DriftProLoadingCenter()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _countHeader(
                    context,
                    upcoming: _upcoming.length,
                    past: _past.length,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Kommende',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: muted,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_upcoming.isEmpty)
                    _emptyBox(context, 'Ingen planlagte møter')
                  else
                    ..._upcoming.map((m) => _tile(context, m, highlight: true)),
                  const SizedBox(height: 20),
                  Text(
                    'Tidligere',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: muted,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_past.isEmpty)
                    _emptyBox(context, 'Ingen tidligere møter')
                  else
                    ..._past.map((m) => _tile(context, m)),
                ],
              ),
            ),
    );
  }

  Widget _countHeader(
    BuildContext context, {
    required int upcoming,
    required int past,
  }) {
    return Row(
      children: [
        Expanded(
          child: _statChip(
            context,
            icon: Icons.event_available_outlined,
            label: 'Kommende',
            value: '$upcoming',
            accent: DriftProTheme.primaryGreen,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statChip(
            context,
            icon: Icons.history,
            label: 'Tidligere',
            value: '$past',
            accent: Colors.blueGrey,
          ),
        ),
      ],
    );
  }

  Widget _statChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: PartnerUi.mutedText(context))),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyBox(BuildContext context, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: PartnerUi.mutedText(context)),
      ),
    );
  }

  Widget _tile(BuildContext context, PartnerMeeting m, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: highlight
            ? DriftProTheme.primaryGreen.withValues(alpha: 0.06)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: highlight
                  ? DriftProTheme.primaryGreen.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                m.isAudit ? Icons.fact_check_outlined : Icons.event_outlined,
                color: DriftProTheme.primaryGreen,
              ),
            ),
            title: Text(m.title, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${PartnerMeeting.meetingTypeLabel(m.meetingType)}\n'
                '${ownerFmtDateTime(m.scheduledAt)}',
                style: TextStyle(
                  height: 1.35,
                  color: PartnerUi.mutedText(context),
                ),
              ),
            ),
            isThreeLine: true,
            trailing: PartnerStatusBadge(
              label: PartnerMeeting.statusLabel(m.status),
              color: DriftProTheme.info,
            ),
          ),
        ),
      ),
    );
  }
}
