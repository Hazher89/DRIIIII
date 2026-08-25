import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import '../profile/widgets/notification_audit_panel.dart';
import '../profile/widgets/notification_settings_split_tab.dart';
import 'partner_sms_compose_screen.dart';
import 'widgets/partner_email_log_panel.dart';
import 'widgets/partner_modern_ui.dart';
import 'widgets/partner_sms_hub_ui.dart';
import 'widgets/partner_sms_log_panel.dart';

/// SMS-hub med tydelige faner: Send, logg, feilet og innstillinger.
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

class _PartnerSmsHubScreenState extends State<PartnerSmsHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  List<_SmsHubTab> get _tabDefs {
    final tabs = <_SmsHubTab>[
      const _SmsHubTab(
        label: 'Send',
        icon: Icons.send_rounded,
      ),
      const _SmsHubTab(
        label: 'SMS-logg',
        icon: Icons.history_rounded,
      ),
    ];
    if (widget.canManageNotifications) {
      tabs.addAll(const [
        _SmsHubTab(label: 'E-post', icon: Icons.email_outlined),
        _SmsHubTab(label: 'Ikke sendt', icon: Icons.error_outline_rounded),
        _SmsHubTab(label: 'Innstillinger', icon: Icons.tune_rounded),
      ]);
    }
    return tabs;
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabDefs.length, vsync: this);
  }

  @override
  void didUpdateWidget(covariant PartnerSmsHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.canManageNotifications != widget.canManageNotifications) {
      final len = _tabDefs.length;
      if (_tabs.length != len) {
        final oldIndex = _tabs.index.clamp(0, len - 1);
        _tabs.dispose();
        _tabs = TabController(length: len, vsync: this, initialIndex: oldIndex);
      }
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = widget.partners.where((p) => p.isActive).length;
    final defs = _tabDefs;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: DriftProTheme.primaryGreen,
            indicatorWeight: 3,
            labelColor: DriftProTheme.primaryGreenDark,
            unselectedLabelColor: PartnerModernUi.muted(context),
            labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            unselectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            tabs: [
              for (final t in defs)
                Tab(
                  height: 46,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(t.icon, size: 18),
                      const SizedBox(width: 8),
                      Text(t.label),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: PartnerModernUi.border(context)),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildSendPane(activePartners: active),
              PartnerSmsLogPanel(partners: widget.partners),
              if (widget.canManageNotifications) ...[
                PartnerEmailLogPanel(partners: widget.partners),
                const NotificationAuditPanel(partnerScopeOnly: true),
                const NotificationSettingsSplitTab(),
              ],
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(title: const Text('Samarbeid — SMS')),
      body: body,
    );
  }

  Widget _buildSendPane({required int activePartners}) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        PartnerSmsHubHeader(
          partnerCount: widget.partners.length,
          activePartners: activePartners,
        ),
        const PartnerSmsComposeScreen(
          embedded: true,
          hubEmbedded: true,
        ),
      ],
    );
  }
}

class _SmsHubTab {
  const _SmsHubTab({required this.label, required this.icon});

  final String label;
  final IconData icon;
}
