import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import '../profile/widgets/notification_audit_panel.dart';
import '../profile/widgets/notification_settings_split_tab.dart';
import 'partner_sms_compose_screen.dart';
import 'widgets/partner_email_log_panel.dart';
import 'widgets/partner_sms_hub_ui.dart';
import 'widgets/partner_sms_log_panel.dart';

/// SMS-hub: én scrollbar side — send er hovedinnhold, logg åpnes på egne sider.
class PartnerSmsHubScreen extends StatefulWidget {
  final List<Partner> partners;
  final bool embedded;
  final bool nestedScroll;
  final bool canManageNotifications;

  const PartnerSmsHubScreen({
    super.key,
    required this.partners,
    this.embedded = true,
    this.nestedScroll = false,
    this.canManageNotifications = false,
  });

  @override
  State<PartnerSmsHubScreen> createState() => _PartnerSmsHubScreenState();
}

class _PartnerSmsHubScreenState extends State<PartnerSmsHubScreen> {
  void _openPage({
    required String title,
    required Widget body,
  }) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          backgroundColor: Theme.of(ctx).brightness == Brightness.dark
              ? DriftProTheme.surfaceDark
              : DriftProTheme.surfaceLight,
          appBar: AppBar(title: Text(title)),
          body: body,
        ),
      ),
    );
  }

  void _openSmsLog() {
    _openPage(
      title: 'SMS-logg',
      body: PartnerSmsLogPanel(partners: widget.partners),
    );
  }

  void _openEmailLog() {
    _openPage(
      title: 'E-post-logg',
      body: PartnerEmailLogPanel(partners: widget.partners),
    );
  }

  void _openFailed() {
    _openPage(
      title: 'Ikke sendt',
      body: const NotificationAuditPanel(partnerScopeOnly: true),
    );
  }

  void _openSettings() {
    _openPage(
      title: 'Varselinnstillinger',
      body: const NotificationSettingsSplitTab(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = widget.partners.where((p) => p.isActive).length;

    final slivers = <Widget>[
      if (widget.nestedScroll)
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
      SliverToBoxAdapter(
        child: PartnerSmsHubHero(
          partnerCount: widget.partners.length,
          activePartners: active,
          onOpenLog: _openSmsLog,
          onOpenSettings: widget.canManageNotifications ? _openSettings : null,
        ),
      ),
      SliverToBoxAdapter(
        child: PartnerSmsHubActionGrid(
          onSmsLog: _openSmsLog,
          onEmailLog: widget.canManageNotifications ? _openEmailLog : null,
          onFailed: widget.canManageNotifications ? _openFailed : null,
          onSettings: widget.canManageNotifications ? _openSettings : null,
        ),
      ),
      SliverToBoxAdapter(
        child: PartnerSmsHubSectionTitle(
          title: 'Send SMS',
          subtitle: '1. Velg MAVI · 2. Velg mottakere · 3. Skriv melding · 4. Send',
        ),
      ),
      SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          decoration: BoxDecoration(
            color: isDark ? DriftProTheme.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? DriftProTheme.dividerDark : const Color(0xFFE5E7EB),
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          clipBehavior: Clip.antiAlias,
          child: const PartnerSmsComposeScreen(
            embedded: true,
            hubEmbedded: true,
          ),
        ),
      ),
    ];

    final scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: slivers,
    );

    if (widget.embedded) return scroll;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(title: const Text('Samarbeid — SMS')),
      body: scroll,
    );
  }
}
