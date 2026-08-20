import 'package:flutter/material.dart';

import '../../core/routing/app_paths.dart';
import '../../core/routing/route_url_sync.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/email_outbox_log_panel.dart';
import 'widgets/notification_audit_panel.dart';
import 'widgets/notification_settings_split_tab.dart';
import 'widgets/sms_outbox_log_panel.dart';
import '../../core/layout/web_layout.dart';

/// Superadmin: logg + innstillinger (MAVI og samarbeid adskilt).
class ProfileNotificationsTab extends StatefulWidget {
  const ProfileNotificationsTab({
    super.key,
    this.initialTab,
    this.initialSettingsTab,
  });

  final String? initialTab;
  final String? initialSettingsTab;

  @override
  State<ProfileNotificationsTab> createState() => _ProfileNotificationsTabState();
}

class _ProfileNotificationsTabState extends State<ProfileNotificationsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    final idx = RouteUrlSync.indexForSlug(widget.initialTab, AppPaths.varslerTabs);
    _tabs = TabController(length: 4, vsync: this, initialIndex: idx);
    _tabs.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncUrl());
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging || !mounted) return;
    _syncUrl();
  }

  void _syncUrl() {
    if (!mounted) return;
    final tab = RouteUrlSync.slugForIndex(_tabs.index, AppPaths.varslerTabs);
    RouteUrlSync.goIfChanged(context, AppPaths.varslerPath(tab: tab));
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
          child: TabBar(
            controller: _tabs,
            labelColor: DriftProTheme.primaryGreen,
            unselectedLabelColor: Colors.grey,
            indicatorColor: DriftProTheme.primaryGreen,
            isScrollable: true,
            tabs: const [
              Tab(icon: Icon(Icons.sms_outlined, size: 20), text: 'SMS-logg'),
              Tab(icon: Icon(Icons.email_outlined, size: 20), text: 'E-post-logg'),
              Tab(icon: Icon(Icons.block, size: 20), text: 'Ikke sendt'),
              Tab(icon: Icon(Icons.tune, size: 20), text: 'Innstillinger'),
            ],
          ),
        ),
        Expanded(
          child: DriftProTabView(
            controller: _tabs,
            children: [
              const SmsOutboxLogPanel(),
              const EmailOutboxLogPanel(),
              const NotificationAuditPanel(),
              NotificationSettingsSplitTab(
                initialTab: widget.initialSettingsTab,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
