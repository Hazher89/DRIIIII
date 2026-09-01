import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/home_feed_service.dart';
import '../../core/services/storage/storage_file_actions.dart';
import '../../core/theme/app_theme.dart';
import '../../models/home_feed_item.dart';
import '../../models/home_feed_layout_config.dart';
import '../platform_media_view.dart';

/// Én forside-rad — brukes i app, web og admin-forhåndsvisning.
class HomeFeedItemView extends StatefulWidget {
  const HomeFeedItemView({
    super.key,
    required this.item,
    required this.layout,
    this.previewPlatform = HomeFeedPreviewPlatform.auto,
    this.compactPreview = false,
    this.interactive = true,
  });

  final HomeFeedItem item;
  final HomeFeedLayoutConfig layout;
  final HomeFeedPreviewPlatform previewPlatform;
  final bool compactPreview;
  final bool interactive;

  @override
  State<HomeFeedItemView> createState() => _HomeFeedItemViewState();
}

class _HomeFeedItemViewState extends State<HomeFeedItemView> {
  String? _url;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant HomeFeedItemView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.storagePath != widget.item.storagePath) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    if (!widget.item.contentType.needsMedia ||
        widget.item.storagePath.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final url = await HomeFeedService.resolveDisplayUrl(widget.item.storagePath);
    if (!mounted) return;
    setState(() {
      _url = url;
      _loading = false;
    });
  }

  Future<void> _openDocument() async {
    if (!widget.interactive) return;
    await StorageFileActions.open(
      context,
      storagePath: widget.item.storagePath,
      title: widget.item.title.isNotEmpty
          ? widget.item.title
          : widget.item.fileName ?? 'Dokument',
    );
  }

  Future<void> _openMedia() async {
    if (!widget.interactive || _url == null) return;
    await launchUrl(Uri.parse(_url!), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final layout = widget.layout;
    final item = widget.item;
    final isWeb = widget.previewPlatform == HomeFeedPreviewPlatform.web ||
        (widget.previewPlatform == HomeFeedPreviewPlatform.auto &&
            MediaQuery.sizeOf(context).width >= 720);

    final height = layout.resolveHeight(
      isWeb: isWeb,
      compactPreview: widget.compactPreview,
    );
    final radius = layout.edgeToEdge || layout.fullPageHero
        ? 0.0
        : layout.borderRadius;

    final hasTitle = item.title.isNotEmpty;
    final hasCaption = item.caption?.isNotEmpty ?? false;
    final showText = layout.textPosition != HomeFeedTextPosition.hidden &&
        (hasTitle || hasCaption);
    final textBelow =
        showText && layout.textPosition == HomeFeedTextPosition.below;
    final textOverlay = showText && layout.textPosition.isOverlay;

    Widget mediaArea = _loading
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
        : _buildMedia(isDark);

    if (textOverlay) {
      mediaArea = Stack(
        fit: StackFit.expand,
        children: [
          mediaArea,
          if (layout.overlayOpacity > 0)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: _overlayGradient(layout),
              ),
            ),
          _buildTextBlock(isDark, overlay: true),
        ],
      );
    }

    final card = Material(
      color: isDark ? DriftProTheme.cardDark : DriftProTheme.cardLight,
      elevation: layout.fullPageHero ? 0 : 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: !widget.interactive
            ? null
            : item.contentType == HomeFeedContentType.document
                ? _openDocument
                : _url != null
                    ? _openMedia
                    : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: height,
              width: double.infinity,
              child: mediaArea,
            ),
            if (textBelow) _buildTextBlock(isDark, overlay: false),
          ],
        ),
      ),
    );

    return card;
  }

  LinearGradient _overlayGradient(HomeFeedLayoutConfig layout) {
    final c = layout.overlayColor;
    switch (layout.textPosition) {
      case HomeFeedTextPosition.overlayTop:
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c, c.withValues(alpha: 0)],
          stops: const [0, 0.55],
        );
      case HomeFeedTextPosition.overlayCenter:
        return LinearGradient(
          colors: [
            c.withValues(alpha: layout.overlayOpacity * 0.2),
            c,
            c.withValues(alpha: layout.overlayOpacity * 0.2),
          ],
        );
      case HomeFeedTextPosition.overlayBottom:
        return LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [c, c.withValues(alpha: 0)],
          stops: const [0, 0.55],
        );
      default:
        return LinearGradient(colors: [c, c]);
    }
  }

  Widget _buildTextBlock(bool isDark, {required bool overlay}) {
    final item = widget.item;
    final layout = widget.layout;
    final fallbackTitle = isDark ? Colors.white : Colors.black87;
    final fallbackCaption = isDark ? Colors.grey[400]! : Colors.grey[700]!;

    final titleStyle = layout.titleStyle.toTextStyle(fallback: fallbackTitle);
    final captionStyle =
        layout.captionStyle.toTextStyle(fallback: fallbackCaption);

    Alignment align;
    switch (layout.textAlign) {
      case TextAlign.center:
        align = overlay
            ? Alignment.center
            : Alignment.centerLeft;
      case TextAlign.right:
      case TextAlign.end:
        align = overlay ? Alignment.centerRight : Alignment.centerRight;
      default:
        align = overlay ? Alignment.bottomLeft : Alignment.centerLeft;
    }

    if (overlay) {
      switch (layout.textPosition) {
        case HomeFeedTextPosition.overlayTop:
          align = layout.textAlign == TextAlign.center
              ? Alignment.topCenter
              : layout.textAlign == TextAlign.right
                  ? Alignment.topRight
                  : Alignment.topLeft;
        case HomeFeedTextPosition.overlayCenter:
          align = layout.textAlign == TextAlign.center
              ? Alignment.center
              : layout.textAlign == TextAlign.right
                  ? Alignment.centerRight
                  : Alignment.centerLeft;
        case HomeFeedTextPosition.overlayBottom:
          align = layout.textAlign == TextAlign.center
              ? Alignment.bottomCenter
              : layout.textAlign == TextAlign.right
                  ? Alignment.bottomRight
                  : Alignment.bottomLeft;
        default:
          break;
      }
    }

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: layout.textAlign == TextAlign.center
          ? CrossAxisAlignment.center
          : layout.textAlign == TextAlign.right
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
      children: [
        if (item.title.isNotEmpty)
          Text(
            item.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: layout.textAlign,
            style: titleStyle,
          ),
        if (item.caption?.isNotEmpty ?? false) ...[
          if (item.title.isNotEmpty) const SizedBox(height: 4),
          Text(
            item.caption!,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            textAlign: layout.textAlign,
            style: captionStyle,
          ),
        ],
      ],
    );

    if (overlay) {
      return Align(
        alignment: align,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: content,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: content,
    );
  }

  Widget _buildMedia(bool isDark) {
    final item = widget.item;
    final url = _url;
    final fit = widget.layout.mediaFit.boxFit;

    switch (item.contentType) {
      case HomeFeedContentType.image:
        if (url == null) {
          return const Center(child: Icon(Icons.broken_image_outlined));
        }
        return Image.network(
          url,
          fit: fit,
          width: double.infinity,
          height: double.infinity,
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
      case HomeFeedContentType.text:
      case HomeFeedContentType.youtube:
      case HomeFeedContentType.link:
      case HomeFeedContentType.spacer:
      case HomeFeedContentType.carousel:
        return const SizedBox.shrink();
    }
  }
}
