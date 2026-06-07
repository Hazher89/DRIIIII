import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/open_external_url.dart';

Future<void> launchInfoEmail(String email, {String subject = 'DriftPro'}) async {
  final uri = Uri.parse('mailto:$email?subject=${Uri.encodeComponent(subject)}');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else {
    await openExternalUrl(uri.toString());
  }
}

/// Felles layout for Hjelp, Personvern og Om-sider.
class InfoPageScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;
  final Widget? footer;

  const InfoPageScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 14),
              title: Text(
                title,
                style: DriftProTheme.headingSm.copyWith(
                  color: Colors.white,
                  fontSize: 17,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: DriftProTheme.primaryGradient,
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 56, 20, 48),
                    child: Row(
                      children: [
                        Icon(icon, color: Colors.white70, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            subtitle,
                            style: DriftProTheme.bodySm.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                ...children,
                if (footer != null) ...[const SizedBox(height: 8), footer!],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class InfoSection extends StatelessWidget {
  final String title;
  final String? lead;
  final List<String> paragraphs;
  final List<String> bullets;
  final IconData? icon;

  const InfoSection({
    super.key,
    required this.title,
    this.lead,
    this.paragraphs = const [],
    this.bullets = const [],
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: DriftProTheme.primaryGreen),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(title, style: DriftProTheme.headingSm),
              ),
            ],
          ),
          if (lead != null) ...[
            const SizedBox(height: 10),
            Text(
              lead!,
              style: DriftProTheme.bodyMd.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          ...paragraphs.map(
            (p) => Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(p, style: DriftProTheme.bodyMd),
            ),
          ),
          ...bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Icon(Icons.circle, size: 6, color: DriftProTheme.primaryGreen),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(b, style: DriftProTheme.bodyMd)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class InfoContactCard extends StatelessWidget {
  final String email;
  final String hint;

  const InfoContactCard({super.key, required this.email, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            DriftProTheme.primaryGreen.withValues(alpha: 0.12),
            DriftProTheme.primaryGreen.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(hint, style: DriftProTheme.bodyMd),
          const SizedBox(height: 12),
          SelectableText(
            email,
            style: DriftProTheme.labelLg.copyWith(
              color: DriftProTheme.primaryGreen,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
