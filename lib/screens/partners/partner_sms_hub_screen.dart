import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import 'partner_sms_compose_screen.dart';
import 'widgets/partner_modern_ui.dart';
import 'widgets/partner_sms_log_panel.dart';
import 'widgets/partner_ui.dart';

/// Samarbeid: send SMS + logg (kun partner-scope).
class PartnerSmsHubScreen extends StatefulWidget {
  final List<Partner> partners;
  final bool embedded;

  const PartnerSmsHubScreen({
    super.key,
    required this.partners,
    this.embedded = true,
  });

  @override
  State<PartnerSmsHubScreen> createState() => _PartnerSmsHubScreenState();
}

class _PartnerSmsHubScreenState extends State<PartnerSmsHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _showAllSections = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PartnerModernKpiGrid(
          items: [
            ('Bedrifter', '${widget.partners.length}'),
            ('Kan sende', '${widget.partners.where((p) => p.isActive).length}'),
            ('Hub', 'SMS'),
            ('Status', 'Klar'),
          ],
        ),
        AnimatedBuilder(
          animation: _tabs,
          builder: (context, _) {
            final current = _tabs.index == 0 ? 'Send SMS' : 'SMS-logg';
            return PartnerSmartSectionPicker(
              title: 'Viser',
              currentLabel: current,
              onPick: () async {
                final selected = await showModalBottomSheet<int>(
                  context: context,
                  showDragHandle: true,
                  builder: (ctx) => SafeArea(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.edit_note_outlined),
                          title: const Text('Send SMS'),
                          onTap: () => Navigator.of(ctx).pop(0),
                        ),
                        ListTile(
                          leading: const Icon(Icons.history),
                          title: const Text('SMS-logg'),
                          onTap: () => Navigator.of(ctx).pop(1),
                        ),
                      ],
                    ),
                  ),
                );
                if (selected != null && mounted) _tabs.animateTo(selected);
              },
              onToggleAll: () => setState(() => _showAllSections = !_showAllSections),
              showAll: _showAllSections,
            );
          },
        ),
        if (_showAllSections)
          Material(
            color: isDark ? DriftProTheme.cardDark : Colors.white,
            child: TabBar(
              controller: _tabs,
              indicatorColor: DriftProTheme.primaryGreen,
              labelColor: DriftProTheme.primaryGreenDark,
              unselectedLabelColor: PartnerUi.mutedText(context),
              tabs: const [
                Tab(icon: Icon(Icons.edit_note_outlined, size: 20), text: 'Send SMS'),
                Tab(icon: Icon(Icons.history, size: 20), text: 'SMS-logg'),
              ],
            ),
          ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              const PartnerSmsComposeScreen(embedded: true),
              PartnerSmsLogPanel(partners: widget.partners),
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(title: const Text('Samarbeid — SMS')),
      body: body,
    );
  }
}
