import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/home_feed_service.dart';
import '../models/home_feed_item.dart';
import '../models/home_feed_layout_config.dart';
import 'home_feed/home_feed_block_view.dart';

/// Live forside-innhold fra Supabase — grid, karusell, shuffle og rotasjon.
class HomeFeedBanner extends StatefulWidget {
  const HomeFeedBanner({
    super.key,
    required this.audience,
    this.portal,
    this.compact = false,
    this.previewPlatform = HomeFeedPreviewPlatform.auto,
  });

  final HomeFeedAudience audience;
  final String? portal;
  final bool compact;
  final HomeFeedPreviewPlatform previewPlatform;

  @override
  State<HomeFeedBanner> createState() => _HomeFeedBannerState();
}

class _HomeFeedBannerState extends State<HomeFeedBanner> {
  List<HomeFeedItem> _items = const [];
  bool _loading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = HomeFeedService.subscribe(
      audience: widget.audience,
      onChanged: _load,
    );
  }

  @override
  void dispose() {
    HomeFeedService.unsubscribe(_channel);
    super.dispose();
  }

  @override
  void didUpdateWidget(HomeFeedBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audience != widget.audience ||
        oldWidget.portal != widget.portal) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final items = await HomeFeedService.fetchFeed(
        widget.audience,
        portal: widget.portal,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  bool _resolveIsWeb(BuildContext context) {
    switch (widget.previewPlatform) {
      case HomeFeedPreviewPlatform.web:
        return true;
      case HomeFeedPreviewPlatform.app:
        return false;
      case HomeFeedPreviewPlatform.auto:
        return kIsWeb || MediaQuery.sizeOf(context).width >= 900;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _items.isEmpty) return const SizedBox.shrink();

    final isWeb = _resolveIsWeb(context);
    final padding = _items.isNotEmpty
        ? _items.first.layoutConfig.resolvePadding(isWeb: isWeb)
        : const EdgeInsets.symmetric(horizontal: 16);

    return Padding(
      padding: widget.compact
          ? const EdgeInsets.fromLTRB(0, 8, 0, 8)
          : padding,
      child: _HomeFeedSceneGrid(
        items: _items,
        isWeb: isWeb,
        previewPlatform: widget.previewPlatform,
        compactPreview: widget.compact,
      ),
    );
  }
}

class _HomeFeedSceneGrid extends StatelessWidget {
  const _HomeFeedSceneGrid({
    required this.items,
    required this.isWeb,
    required this.previewPlatform,
    required this.compactPreview,
  });

  final List<HomeFeedItem> items;
  final bool isWeb;
  final HomeFeedPreviewPlatform previewPlatform;
  final bool compactPreview;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 12;
        const gap = 10.0;

        final rows = <List<HomeFeedItem>>[];
        var currentRow = <HomeFeedItem>[];
        var usedCols = 0;

        for (final item in items) {
          final span = item.layoutConfig.resolveColSpan(isWeb: isWeb);
          if (usedCols + span > columns && currentRow.isNotEmpty) {
            rows.add(currentRow);
            currentRow = [];
            usedCols = 0;
          }
          currentRow.add(item);
          usedCols += span;
          if (usedCols >= columns) {
            rows.add(currentRow);
            currentRow = [];
            usedCols = 0;
          }
        }
        if (currentRow.isNotEmpty) rows.add(currentRow);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) SizedBox(height: gap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < rows[r].length; i++) ...[
                    if (i > 0) SizedBox(width: gap),
                    Expanded(
                      flex: rows[r][i].layoutConfig.resolveColSpan(isWeb: isWeb),
                      child: HomeFeedBlockView(
                        item: rows[r][i],
                        previewPlatform: previewPlatform,
                        compactPreview: compactPreview,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
