import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../models/home_feed_content_config.dart';
import '../../models/home_feed_item.dart';
import '../../models/home_feed_layout_config.dart';
import 'home_feed_item_view.dart';
import '../youtube_embed_view.dart';

/// Renderer for alle blokktyper inkl. karusell.
class HomeFeedBlockView extends StatelessWidget {
  const HomeFeedBlockView({
    super.key,
    required this.item,
    this.previewPlatform = HomeFeedPreviewPlatform.auto,
    this.compactPreview = false,
    this.interactive = true,
  });

  final HomeFeedItem item;
  final HomeFeedPreviewPlatform previewPlatform;
  final bool compactPreview;
  final bool interactive;

  bool _isWeb(BuildContext context) {
    switch (previewPlatform) {
      case HomeFeedPreviewPlatform.web:
        return true;
      case HomeFeedPreviewPlatform.app:
        return false;
      case HomeFeedPreviewPlatform.auto:
        return kIsWeb || MediaQuery.sizeOf(context).width >= 720;
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (item.contentType) {
      case HomeFeedContentType.carousel:
        return HomeFeedCarouselView(
          item: item,
          previewPlatform: previewPlatform,
          compactPreview: compactPreview,
          interactive: interactive,
        );
      case HomeFeedContentType.spacer:
        final h = _isWeb(context)
            ? item.contentConfig.spacer.heightWeb
            : item.contentConfig.spacer.heightApp;
        return SizedBox(height: h);
      case HomeFeedContentType.text:
        return _TextBlockView(
          item: item,
          layout: item.layoutConfig,
          isWeb: _isWeb(context),
          interactive: interactive,
        );
      case HomeFeedContentType.youtube:
        return _YoutubeBlockView(
          item: item,
          layout: item.layoutConfig,
          isWeb: _isWeb(context),
          compactPreview: compactPreview,
          interactive: interactive,
        );
      case HomeFeedContentType.link:
        return _LinkBlockView(
          item: item,
          layout: item.layoutConfig,
          interactive: interactive,
        );
      default:
        return HomeFeedItemView(
          item: item,
          layout: item.layoutConfig,
          previewPlatform: previewPlatform,
          compactPreview: compactPreview,
          interactive: interactive,
        );
    }
  }
}

class HomeFeedCarouselView extends StatefulWidget {
  const HomeFeedCarouselView({
    super.key,
    required this.item,
    this.previewPlatform = HomeFeedPreviewPlatform.auto,
    this.compactPreview = false,
    this.interactive = true,
  });

  final HomeFeedItem item;
  final HomeFeedPreviewPlatform previewPlatform;
  final bool compactPreview;
  final bool interactive;

  @override
  State<HomeFeedCarouselView> createState() => _HomeFeedCarouselViewState();
}

class _HomeFeedCarouselViewState extends State<HomeFeedCarouselView> {
  late PageController _pageController;
  Timer? _timer;
  int _page = 0;
  late List<HomeFeedItem> _slides;

  @override
  void initState() {
    super.initState();
    _slides = _resolveSlides();
    _pageController = PageController();
    _startAutoRotate();
  }

  @override
  void didUpdateWidget(HomeFeedCarouselView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.carouselSlides != widget.item.carouselSlides) {
      _slides = _resolveSlides();
      _restartTimer();
    }
  }

  List<HomeFeedItem> _resolveSlides() {
    final slides = widget.item.carouselSlides;
    if (slides.isEmpty) return const [];
    final cfg = widget.item.contentConfig.carousel;
    if (cfg.mode == HomeFeedCarouselMode.shuffle ||
        cfg.mode == HomeFeedCarouselMode.weighted) {
      final ids = cfg.shuffledSlideIds();
      final byId = {for (final s in slides) s.id: s};
      return ids.map((id) => byId[id]).whereType<HomeFeedItem>().toList();
    }
    return slides;
  }

  void _startAutoRotate() {
    _timer?.cancel();
    final mode = widget.item.contentConfig.carousel.mode;
    if (mode != HomeFeedCarouselMode.rotate &&
        mode != HomeFeedCarouselMode.shuffle &&
        mode != HomeFeedCarouselMode.weighted) {
      return;
    }
    final ms = widget.item.contentConfig.carousel.intervalMs;
    _timer = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (!mounted || _slides.length < 2) return;
      final next = (_page + 1) % _slides.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _restartTimer() {
    _timer?.cancel();
    _startAutoRotate();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  bool _isWeb(BuildContext context) {
    return widget.previewPlatform == HomeFeedPreviewPlatform.web ||
        (widget.previewPlatform == HomeFeedPreviewPlatform.auto &&
            MediaQuery.sizeOf(context).width >= 720);
  }

  @override
  Widget build(BuildContext context) {
    if (_slides.isEmpty) {
      return Container(
        height: widget.item.layoutConfig.resolveHeight(
          isWeb: _isWeb(context),
          compactPreview: widget.compactPreview,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('Karusell uten slides'),
      );
    }

    final height = widget.item.layoutConfig.resolveHeight(
      isWeb: _isWeb(context),
      compactPreview: widget.compactPreview,
    );

    return Column(
      children: [
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: _pageController,
            itemCount: _slides.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, index) {
              final slide = _slides[index];
              return HomeFeedBlockView(
                item: slide,
                previewPlatform: widget.previewPlatform,
                compactPreview: widget.compactPreview,
                interactive: widget.interactive,
              );
            },
          ),
        ),
        if (_slides.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_slides.length, (i) {
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
    );
  }
}

class _TextBlockView extends StatelessWidget {
  const _TextBlockView({
    required this.item,
    required this.layout,
    required this.isWeb,
    required this.interactive,
  });

  final HomeFeedItem item;
  final HomeFeedLayoutConfig layout;
  final bool isWeb;
  final bool interactive;

  Color _themeBg(HomeFeedThemePreset theme, bool isDark) {
    switch (theme) {
      case HomeFeedThemePreset.maviGreen:
        return DriftProTheme.primaryGreen.withValues(alpha: 0.12);
      case HomeFeedThemePreset.info:
        return DriftProTheme.info.withValues(alpha: 0.15);
      case HomeFeedThemePreset.warning:
        return DriftProTheme.warning.withValues(alpha: 0.2);
      case HomeFeedThemePreset.danger:
        return DriftProTheme.error.withValues(alpha: 0.12);
      case HomeFeedThemePreset.custom:
        final cfg = item.contentConfig.textBlock;
        return _parseHex(cfg.backgroundColorHex, cfg.backgroundOpacity);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cfg = item.contentConfig.textBlock;
    final height = layout.resolveHeight(isWeb: isWeb);
    final radius = layout.borderRadius;

    return Container(
      constraints: BoxConstraints(minHeight: height),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _themeBg(cfg.theme, isDark),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.contentConfig.badge.label?.isNotEmpty == true)
            _BadgeRow(item: item),
          if (item.title.isNotEmpty)
            Text(
              item.title,
              style: layout.titleStyle.toTextStyle(
                fallback: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: layout.textAlign,
            ),
          if (cfg.body.isNotEmpty) ...[
            if (item.title.isNotEmpty) const SizedBox(height: 8),
            Text(
              cfg.body,
              maxLines: cfg.maxLines,
              overflow: cfg.maxLines != null ? TextOverflow.ellipsis : null,
              style: layout.captionStyle.toTextStyle(
                fallback: isDark ? Colors.white70 : Colors.black54,
              ),
              textAlign: layout.textAlign,
            ),
          ],
          if (item.caption?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              item.caption!,
              style: DriftProTheme.bodySm.copyWith(
                color: isDark ? Colors.white54 : Colors.grey,
              ),
              textAlign: layout.textAlign,
            ),
          ],
        ],
      ),
    );
  }
}

class _YoutubeBlockView extends StatelessWidget {
  const _YoutubeBlockView({
    required this.item,
    required this.layout,
    required this.isWeb,
    required this.compactPreview,
    required this.interactive,
  });

  final HomeFeedItem item;
  final HomeFeedLayoutConfig layout;
  final bool isWeb;
  final bool compactPreview;
  final bool interactive;

  Future<void> _open(BuildContext context) async {
    if (!interactive) return;
    final yt = item.contentConfig.youtube;
    final url = yt.videoUrl.isNotEmpty
        ? yt.videoUrl
        : 'https://www.youtube.com/watch?v=${yt.resolvedVideoId}';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final yt = item.contentConfig.youtube;
    final videoId = yt.resolvedVideoId;
    final height = layout.resolveHeight(
      isWeb: isWeb,
      compactPreview: compactPreview,
    );
    final radius = layout.edgeToEdge || layout.fullPageHero
        ? 0.0
        : layout.borderRadius;

    if (videoId != null && videoId.isNotEmpty && isWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: YoutubeEmbedView(
          videoId: videoId,
          height: height,
          autoplay: yt.autoplay,
          muted: yt.muted,
        ),
      );
    }

    final thumb = yt.thumbnailUrl;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: interactive ? () => _open(context) : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumb != null)
                Image.network(
                  thumb,
                  fit: layout.mediaFit.boxFit,
                  width: double.infinity,
                  height: height,
                  errorBuilder: (_, __, ___) => _placeholder(),
                )
              else
                _placeholder(),
              Container(
                color: Colors.black.withValues(alpha: 0.25),
                child: Center(
                  child: Icon(
                    videoId == null || videoId.isEmpty
                        ? Icons.videocam_off_outlined
                        : Icons.play_circle_fill,
                    size: videoId == null || videoId.isEmpty ? 48 : 64,
                    color: Colors.white.withValues(
                      alpha: videoId == null || videoId.isEmpty ? 0.5 : 1,
                    ),
                  ),
                ),
              ),
              if (item.title.isNotEmpty)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        layout.titleStyle.toTextStyle(fallback: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: Colors.black87,
      child: const Center(
        child: Icon(Icons.play_circle_outline, color: Colors.white54, size: 48),
      ),
    );
  }
}

class _LinkBlockView extends StatelessWidget {
  const _LinkBlockView({
    required this.item,
    required this.layout,
    required this.interactive,
  });

  final HomeFeedItem item;
  final HomeFeedLayoutConfig layout;
  final bool interactive;

  Future<void> _open(BuildContext context) async {
    if (!interactive) return;
    final link = item.contentConfig.link;
    if (link.internalRoute?.isNotEmpty == true) {
      if (context.mounted) context.go(link.internalRoute!);
      return;
    }
    if (link.url.isEmpty) return;
    await launchUrl(
      Uri.parse(link.url),
      mode: link.openExternal
          ? LaunchMode.externalApplication
          : LaunchMode.platformDefault,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final link = item.contentConfig.link;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (item.title.isNotEmpty)
              Text(
                item.title,
                style: layout.titleStyle.toTextStyle(
                  fallback: isDark ? Colors.white : Colors.black87,
                ),
              ),
            if (item.caption?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                item.caption!,
                style: layout.captionStyle.toTextStyle(
                  fallback: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: interactive ? () => _open(context) : null,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(link.buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeRow extends StatelessWidget {
  const _BadgeRow({required this.item});

  final HomeFeedItem item;

  @override
  Widget build(BuildContext context) {
    final badge = item.contentConfig.badge;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        children: [
          if (badge.label?.isNotEmpty == true)
            Chip(
              label: Text(badge.label!),
              backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.15),
              visualDensity: VisualDensity.compact,
            ),
          if (badge.showCountdown && badge.countdownTarget != null)
            _CountdownChip(target: badge.countdownTarget!),
        ],
      ),
    );
  }
}

class _CountdownChip extends StatefulWidget {
  const _CountdownChip({required this.target});

  final DateTime target;

  @override
  State<_CountdownChip> createState() => _CountdownChipState();
}

class _CountdownChipState extends State<_CountdownChip> {
  Timer? _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    setState(() {
      _remaining = widget.target.difference(DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining.isNegative) {
      return const Chip(
        label: Text('Utløpt'),
        visualDensity: VisualDensity.compact,
      );
    }
    final h = _remaining.inHours;
    final m = _remaining.inMinutes.remainder(60);
    return Chip(
      avatar: const Icon(Icons.timer_outlined, size: 16),
      label: Text('${h}t ${m}m'),
      visualDensity: VisualDensity.compact,
    );
  }
}

Color _parseHex(String hex, double opacity) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) {
    final v = int.tryParse(h, radix: 16);
    if (v != null) {
      return Color(v | 0xFF000000).withValues(alpha: opacity.clamp(0, 1));
    }
  }
  return DriftProTheme.primaryGreen.withValues(alpha: opacity);
}
