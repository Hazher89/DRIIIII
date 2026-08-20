import 'package:flutter/material.dart';

import '../../../core/routing/app_paths.dart';
import '../../../core/routing/route_url_sync.dart';
import '../../../core/theme/app_theme.dart';
import 'employee_notification_recipients_panel.dart';
import 'unified_notification_settings_panel.dart';
import '../../../core/layout/web_layout.dart';

/// Varsel-hub: mottakere per ansatt | firmakanaler | samarbeid.
class NotificationSettingsSplitTab extends StatefulWidget {
  const NotificationSettingsSplitTab({super.key, this.initialTab});

  final String? initialTab;

  @override
  State<NotificationSettingsSplitTab> createState() =>
      _NotificationSettingsSplitTabState();
}

class _NotificationSettingsSplitTabState extends State<NotificationSettingsSplitTab>
    with SingleTickerProviderStateMixin {
  static const _settingsTabs = ['mottakere', 'firmakanaler', 'samarbeid'];
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    final idx = RouteUrlSync.indexForSlug(widget.initialTab, _settingsTabs);
    _tabs = TabController(length: 3, vsync: this, initialIndex: idx);
    _tabs.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging || !mounted) return;
    final settings = RouteUrlSync.slugForIndex(_tabs.index, _settingsTabs);
    RouteUrlSync.goIfChanged(
      context,
      AppPaths.varslerPath(tab: 'innstillinger', settingsTab: settings),
    );
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
          color: Colors.grey.shade100,
          child: TabBar(
            controller: _tabs,
            labelColor: DriftProTheme.primaryGreen,
            unselectedLabelColor: Colors.grey,
            indicatorColor: DriftProTheme.primaryGreen,
            isScrollable: true,
            tabs: const [
              Tab(text: 'Mottakere'),
              Tab(text: 'Firmakanaler'),
              Tab(text: 'Samarbeid'),
            ],
          ),
        ),
        Expanded(
          child: DriftProTabView(
            controller: _tabs,
            children: const [
              EmployeeNotificationRecipientsPanel(),
              UnifiedNotificationSettingsPanel(scope: NotificationSettingsScope.mavi),
              UnifiedNotificationSettingsPanel(scope: NotificationSettingsScope.partner),
            ],
          ),
        ),
      ],
    );
  }
}
