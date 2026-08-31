import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/home_feed_service.dart';
import '../core/theme/app_theme.dart';
import '../models/home_feed_item.dart';
import '../models/home_feed_layout_config.dart';
import 'home_feed/home_feed_item_view.dart';

/// Live forside-innhold fra Supabase — oppdateres uten ny app-bygg.
class HomeFeedBanner extends StatefulWidget {
  const HomeFeedBanner({
    super.key,
    required this.audience,
    this.compact = false,
    this.previewPlatform = HomeFeedPreviewPlatform.auto,
  });

  final HomeFeedAudience audience;
  final bool compact;
  final HomeFeedPreviewPlatform previewPlatform;

  @override
  State<HomeFeedBanner> createState() => _HomeFeedBannerState();
}

class _HomeFeedBannerState extends State<HomeFeedBanner> {
  List<HomeFeedItem> _items = const [];
  bool _loading = true;
  RealtimeChannel? _channel;
  final _pageController = PageController();
  int _page = 0;

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
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await HomeFeedService.fetchFeed(widget.audience);
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
    final maxHeights = _items.map((item) {
      final layout = item.layoutConfig;
      return layout.resolveTotalHeight(
        isWeb: isWeb,
        hasTitle: item.title.isNotEmpty,
        hasCaption: item.caption?.isNotEmpty ?? false,
        compactPreview: widget.compact,
      );
    }).toList();
    final height = maxHeights.reduce((a, b) => a > b ? a : b);
    final padding = _items.isNotEmpty
        ? _items.first.layoutConfig.resolvePadding(isWeb: isWeb)
        : const EdgeInsets.symmetric(horizontal: 16);

    return Padding(
      padding: widget.compact
          ? const EdgeInsets.fromLTRB(0, 8, 0, 8)
          : padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _items.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, index) {
                final item = _items[index];
                return HomeFeedItemView(
                  item: item,
                  layout: item.layoutConfig,
                  previewPlatform: widget.previewPlatform,
                  compactPreview: widget.compact,
                );
              },
            ),
          ),
          if (_items.length > 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_items.length, (i) {
                final activeDot = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: activeDot ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: activeDot
                        ? DriftProTheme.primaryGreen
                        : Colors.grey.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}
