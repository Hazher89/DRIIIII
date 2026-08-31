import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/services/home_feed_service.dart';
import '../core/services/storage/storage_file_actions.dart';
import '../core/theme/app_theme.dart';
import '../models/home_feed_item.dart';
import 'platform_media_view.dart';

/// Live forside-innhold fra Supabase — oppdateres uten ny app-bygg.
class HomeFeedBanner extends StatefulWidget {
  const HomeFeedBanner({
    super.key,
    required this.audience,
    this.compact = false,
  });

  final HomeFeedAudience audience;
  final bool compact;

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

  @override
  Widget build(BuildContext context) {
    if (_loading || _items.isEmpty) return const SizedBox.shrink();

    final height = widget.compact ? 180.0 : 220.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, widget.compact ? 8 : 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _items.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, index) => _FeedCard(
                item: _items[index],
                compact: widget.compact,
              ),
            ),
          ),
          if (_items.length > 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_items.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: active
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

class _FeedCard extends StatefulWidget {
  const _FeedCard({required this.item, required this.compact});

  final HomeFeedItem item;
  final bool compact;

  @override
  State<_FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends State<_FeedCard> {
  String? _url;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _FeedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.storagePath != widget.item.storagePath) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    setState(() => _loading = true);
    final url = await HomeFeedService.resolveDisplayUrl(widget.item.storagePath);
    if (!mounted) return;
    setState(() {
      _url = url;
      _loading = false;
    });
  }

  Future<void> _openDocument() async {
    await StorageFileActions.open(
      context,
      storagePath: widget.item.storagePath,
      title: widget.item.title.isNotEmpty
          ? widget.item.title
          : widget.item.fileName ?? 'Dokument',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final item = widget.item;

    return Material(
      color: isDark ? DriftProTheme.cardDark : DriftProTheme.cardLight,
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.contentType == HomeFeedContentType.document
            ? _openDocument
            : _url != null
                ? () => launchUrl(Uri.parse(_url!), mode: LaunchMode.externalApplication)
                : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _buildMedia(),
            ),
            if (item.title.isNotEmpty || (item.caption?.isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.title.isNotEmpty)
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DriftProTheme.labelLg.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (item.caption?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.caption!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DriftProTheme.bodySm.copyWith(
                          color: isDark ? Colors.grey[400] : Colors.grey[700],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedia() {
    final item = widget.item;
    final url = _url;

    switch (item.contentType) {
      case HomeFeedContentType.image:
        if (url == null) {
          return const Center(child: Icon(Icons.broken_image_outlined));
        }
        return Image.network(
          url,
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (_, __, ___) =>
              const Center(child: Icon(Icons.broken_image_outlined)),
        );
      case HomeFeedContentType.video:
        if (url == null) {
          return const Center(child: Icon(Icons.videocam_off_outlined));
        }
        return PlatformMediaView(url: url);
      case HomeFeedContentType.document:
        return Container(
          color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 48,
                  color: DriftProTheme.primaryGreen,
                ),
                const SizedBox(height: 8),
                Text(
                  item.fileName ?? 'Trykk for å åpne dokument',
                  style: DriftProTheme.bodySm,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
    }
  }
}
