import 'package:flutter/material.dart';

import '../../core/layout/web_layout.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import '../../models/user_profile.dart';
import '../profile/widgets/notification_settings_split_tab.dart';
import 'widgets/partner_deduction_archive_panel.dart';
import 'widgets/partner_deduction_compose_panel.dart';

/// Bot/Trekk — arkiv som hovedside, «Nytt trekk» på egen side (ingen store faner).
class PartnerDeductionHubScreen extends StatefulWidget {
  const PartnerDeductionHubScreen({
    super.key,
    required this.partners,
    required this.profile,
    this.embedded = true,
    this.nestedScroll = false,
    this.canManageNotifications = false,
  });

  final List<Partner> partners;
  final UserProfile? profile;
  final bool embedded;
  final bool nestedScroll;
  final bool canManageNotifications;

  @override
  State<PartnerDeductionHubScreen> createState() => _PartnerDeductionHubScreenState();
}

class _PartnerDeductionHubScreenState extends State<PartnerDeductionHubScreen> {
  int _refreshKey = 0;

  void _openCompose() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          backgroundColor: Theme.of(ctx).brightness == Brightness.dark
              ? DriftProTheme.surfaceDark
              : DriftProTheme.surfaceLight,
          appBar: AppBar(title: const Text('Nytt trekk')),
          body: PartnerDeductionComposePanel(
            partners: widget.partners,
            onCreated: () {
              Navigator.pop(ctx);
              setState(() => _refreshKey++);
            },
          ),
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: const Text('Varselinnstillinger')),
          body: const NotificationSettingsSplitTab(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = PartnerDeductionArchivePanel(
      key: ValueKey(_refreshKey),
      profile: widget.profile,
      partners: widget.partners,
      nestedScroll: widget.nestedScroll,
      canManageNotifications: widget.canManageNotifications,
      onOpenSettings: _openSettings,
      onNewCase: _openCompose,
      onChanged: () => setState(() => _refreshKey++),
    );

    final canvas = WebLayout.prefersPointerNav
        ? WebLayout.canvasColor(context)
        : (Theme.of(context).brightness == Brightness.dark
            ? DriftProTheme.surfaceDark
            : DriftProTheme.surfaceLight);

    if (widget.embedded) {
      return ColoredBox(color: canvas, child: body);
    }

    return Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(title: const Text('Bot / Trekk')),
      body: body,
    );
  }
}
