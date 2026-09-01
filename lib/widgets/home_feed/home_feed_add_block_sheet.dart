import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/home_feed_item.dart';

/// Velg blokktype — tekst, YouTube, media, lenke, karusell, spacer.
Future<HomeFeedContentType?> showHomeFeedAddBlockSheet(
  BuildContext context,
) {
  return showModalBottomSheet<HomeFeedContentType>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Legg til innhold',
                style: DriftProTheme.headingMd,
              ),
              const SizedBox(height: 4),
              Text(
                'Velg type — ingen bilde er påkrevd for tekst, YouTube eller lenker.',
                style: DriftProTheme.bodySm.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              ...HomeFeedContentType.values.map((type) {
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                    child: Icon(type.icon, color: DriftProTheme.primaryGreen),
                  ),
                  title: Text(type.label),
                  subtitle: Text(_subtitleFor(type)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(ctx, type),
                );
              }),
            ],
          ),
        ),
      );
    },
  );
}

String _subtitleFor(HomeFeedContentType type) {
  switch (type) {
    case HomeFeedContentType.text:
      return 'Kun tekst med farger og tema';
    case HomeFeedContentType.youtube:
      return 'Lim inn YouTube-lenke';
    case HomeFeedContentType.image:
      return 'PNG, JPG, WebP, GIF';
    case HomeFeedContentType.video:
      return 'MP4, MOV, WebM';
    case HomeFeedContentType.document:
      return 'PDF eller dokument';
    case HomeFeedContentType.link:
      return 'Knapp med lenke eller intern rute';
    case HomeFeedContentType.spacer:
      return 'Luft mellom elementer';
    case HomeFeedContentType.carousel:
      return 'Flere slides med shuffle/rotasjon';
  }
}
