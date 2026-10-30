import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import '../profile/widgets/notification_audit_panel.dart';
import '../profile/widgets/notification_settings_split_tab.dart';
import 'partner_sms_compose_screen.dart';
import 'widgets/partner_email_log_panel.dart';
import 'widgets/partner_modern_ui.dart';
import 'widgets/partner_sms_log_panel.dart';

/// SMS-hub uten sticky TabBar/hero: topp scroller bort, én seksjon om gangen.
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
  int _section = 0;

  List<_SmsSection> get _sections {
    final list = <_SmsSection>[
      const _SmsSection(
        id: 'send',
        label: 'Send SMS',
        icon: Icons.send_rounded,
        blurb:
            'Velg kontakter på en MAVI, eller kunder fra dagens rute-PDF. '
            'Skriv melding og send — det dukker opp i SMS-loggen etterpå.',
      ),
      const _SmsSection(
        id: 'log',
        label: 'SMS-logg',
        icon: Icons.history_rounded,
        blurb:
            'Alle SMS sendt fra samarbeid: ruter, manuell sending, portal og møter. '
            'Bruk filter hvis du leter etter én bedrift eller status.',
      ),
    ];
    if (widget.canManageNotifications) {
      list.addAll(const [
        _SmsSection(
          id: 'email',
          label: 'E-postlogg',
          icon: Icons.email_outlined,
          blurb:
              'Utgående e-post til partnere (f.eks. rutevarsler). '
              'Åpne en rad for å lese hele meldingen.',
        ),
        _SmsSection(
          id: 'failed',
          label: 'Ikke sendt',
          icon: Icons.error_outline_rounded,
          blurb:
              'Varsler som ble hoppet over eller ligger i kø. '
              'Her ser du hvorfor noe ikke gikk ut.',
        ),
        _SmsSection(
          id: 'settings',
          label: 'Innstillinger',
          icon: Icons.tune_rounded,
          blurb:
              'Styr hvem som skal få SMS og e-post ved ruter og andre hendelser.',
        ),
      ]);
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? DriftProTheme.surfaceDark : const Color(0xFFF4F6F8);
    final sections = _sections;
    if (_section >= sections.length) _section = 0;
    final current = sections[_section];
    final active = widget.partners.where((p) => p.isActive).length;

    final body = ColoredBox(
      color: bg,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) {
          return [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SMS',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.4,
                                  color: PartnerModernUi.textPrimary(context),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Send meldinger og følg loggen. Velg en seksjon — '
                                'toppen scroller bort når du blar ned.',
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: PartnerModernUi.muted(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: DriftProTheme.primaryGreen
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$active aktive',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: DriftProTheme.primaryGreenDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < sections.length; i++)
                          ChoiceChip(
                            avatar: Icon(sections[i].icon, size: 16),
                            label: Text(sections[i].label),
                            selected: _section == i,
                            onSelected: (_) => setState(() => _section = i),
                            selectedColor: DriftProTheme.primaryGreen
                                .withValues(alpha: 0.22),
                            visualDensity: VisualDensity.compact,
                            labelStyle: TextStyle(
                              fontWeight: _section == i
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: PartnerModernUi.surface(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: PartnerModernUi.border(context),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lightbulb_outline_rounded,
                            size: 18,
                            color: PartnerModernUi.muted(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  current.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: PartnerModernUi.textPrimary(context),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  current.blurb,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.4,
                                    color: PartnerModernUi.muted(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ];
        },
        body: KeyedSubtree(
          key: ValueKey(current.id),
          child: _sectionBody(current.id),
        ),
      ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(title: const Text('SMS')),
      body: body,
    );
  }

  Widget _sectionBody(String id) {
    switch (id) {
      case 'send':
        // Én scrollbar flate — ingen sticky send-banner.
        return const SingleChildScrollView(
          padding: EdgeInsets.only(bottom: 32),
          child: PartnerSmsComposeScreen(
            embedded: true,
            hubEmbedded: true,
          ),
        );
      case 'log':
        return PartnerSmsLogPanel(
          partners: widget.partners,
          compactIntro: true,
        );
      case 'email':
        return PartnerEmailLogPanel(
          partners: widget.partners,
          compactIntro: true,
        );
      case 'failed':
        return const NotificationAuditPanel(
          partnerScopeOnly: true,
          compactIntro: true,
        );
      case 'settings':
        return const NotificationSettingsSplitTab(compactIntro: true);
      default:
        return const SizedBox.shrink();
    }
  }
}

class _SmsSection {
  const _SmsSection({
    required this.id,
    required this.label,
    required this.icon,
    required this.blurb,
  });

  final String id;
  final String label;
  final IconData icon;
  final String blurb;
}
