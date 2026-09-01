import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/home_feed_item.dart';
import '../../models/home_feed_layout_config.dart';
import 'home_feed_block_view.dart';

/// Side-ved-side forhåndsvisning som simulerer mobil (app) og nettleser (web).
class HomeFeedDualPreview extends StatelessWidget {
  const HomeFeedDualPreview({
    super.key,
    required this.item,
    required this.layout,
  });

  final HomeFeedItem item;
  final HomeFeedLayoutConfig layout;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= 720;
        final children = [
          _PreviewFrame(
            label: 'App (mobil)',
            icon: Icons.phone_iphone,
            width: sideBySide ? null : double.infinity,
            child: HomeFeedBlockView(
              item: item,
              previewPlatform: HomeFeedPreviewPlatform.app,
              compactPreview: !sideBySide,
              interactive: false,
            ),
          ),
          _PreviewFrame(
            label: 'Web',
            icon: Icons.laptop_mac,
            width: sideBySide ? null : double.infinity,
            child: HomeFeedBlockView(
              item: item,
              previewPlatform: HomeFeedPreviewPlatform.web,
              compactPreview: !sideBySide,
              interactive: false,
            ),
          ),
        ];

        if (sideBySide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: children[0]),
              const SizedBox(width: 12),
              Expanded(child: children[1]),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            children[0],
            const SizedBox(height: 12),
            children[1],
          ],
        );
      },
    );
  }
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({
    required this.label,
    required this.icon,
    required this.child,
    this.width,
  });

  final String label;
  final IconData icon;
  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : DriftProTheme.cardLight,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : DriftProTheme.dividerLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: DriftProTheme.primaryGreen),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: child,
          ),
        ],
      ),
    );
  }
}
