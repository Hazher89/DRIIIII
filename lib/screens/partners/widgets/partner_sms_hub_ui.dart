import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'partner_modern_ui.dart';

/// Hero for SMS-hub — scroller vekk med siden (ingen faste faner).
class PartnerSmsHubHero extends StatelessWidget {
  final int partnerCount;
  final int activePartners;
  final VoidCallback? onOpenLog;
  final VoidCallback? onOpenSettings;

  const PartnerSmsHubHero({
    super.key,
    required this.partnerCount,
    required this.activePartners,
    this.onOpenLog,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF0F172A), const Color(0xFF1E3A5F), const Color(0xFF0D9488)]
              : [const Color(0xFF0F766E), const Color(0xFF0D9488), const Color(0xFF14B8A6)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D9488).withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.sms_outlined, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SMS til partnere',
                      style: DriftProTheme.headingMd.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Send til sjåfører, bil-eiere og rute-kunder. Logg og varsler åpnes fra hurtigvalg under.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _statChip('$activePartners aktive bedrifter'),
              const SizedBox(width: 8),
              _statChip('$partnerCount totalt'),
            ],
          ),
          if (onOpenLog != null || onOpenSettings != null) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onOpenLog != null)
                  _quickBtn(
                    icon: Icons.history_rounded,
                    label: 'SMS-logg',
                    onTap: onOpenLog!,
                  ),
                if (onOpenSettings != null)
                  _quickBtn(
                    icon: Icons.tune_rounded,
                    label: 'Innstillinger',
                    onTap: onOpenSettings!,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _quickBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 2×2 rutenett med sekundære handlinger — åpner egne sider, ikke faner.
class PartnerSmsHubActionGrid extends StatelessWidget {
  final VoidCallback onSmsLog;
  final VoidCallback? onEmailLog;
  final VoidCallback? onFailed;
  final VoidCallback? onSettings;

  const PartnerSmsHubActionGrid({
    super.key,
    required this.onSmsLog,
    this.onEmailLog,
    this.onFailed,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Logg & administrasjon',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: PartnerModernUi.textPrimary(context),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 520;
              final tiles = <_ActionTile>[
                _ActionTile(
                  icon: Icons.history_rounded,
                  title: 'SMS-logg',
                  subtitle: 'Utgående fra samarbeid',
                  color: const Color(0xFF1565C0),
                  onTap: onSmsLog,
                ),
                if (onEmailLog != null)
                  _ActionTile(
                    icon: Icons.email_outlined,
                    title: 'E-post-logg',
                    subtitle: 'Varsler til partnere',
                    color: const Color(0xFF6A1B9A),
                    onTap: onEmailLog!,
                  ),
                if (onFailed != null)
                  _ActionTile(
                    icon: Icons.error_outline_rounded,
                    title: 'Ikke sendt',
                    subtitle: 'Feilede varsler',
                    color: const Color(0xFFC62828),
                    onTap: onFailed!,
                  ),
                if (onSettings != null)
                  _ActionTile(
                    icon: Icons.notifications_active_outlined,
                    title: 'Varselinnstillinger',
                    subtitle: 'SMS og e-post',
                    color: const Color(0xFF374151),
                    onTap: onSettings!,
                  ),
              ];
              if (wide) {
                return Row(
                  children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: tiles[i]),
                    ],
                  ],
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < tiles.length; i += 2) ...[
                    if (i > 0) const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: tiles[i]),
                        const SizedBox(width: 10),
                        Expanded(
                          child: i + 1 < tiles.length
                              ? tiles[i + 1]
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PartnerModernUi.surface(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: PartnerModernUi.border(context)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: PartnerModernUi.textPrimary(context),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 10,
                        color: PartnerModernUi.muted(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: PartnerModernUi.muted(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class PartnerSmsHubSectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const PartnerSmsHubSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: PartnerModernUi.textPrimary(context),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                color: PartnerModernUi.muted(context),
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
