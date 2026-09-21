import 'package:flutter/material.dart';

import '../../core/services/home_feed_service.dart';
import '../../core/services/storage/storage_file_actions.dart';
import '../../core/theme/app_theme.dart';
import '../../models/home_feed_content_config.dart';
import '../../models/home_feed_item.dart';
import '../../models/home_feed_layout_config.dart';
import '../../screens/chat/widgets/chat_media_viewer.dart';
import '../platform_media_view.dart';
import '../pinch_zoom_in_place.dart';

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
    if (oldWidget.item.storagePath != widget.item.storagePath ||
        oldWidget.item.id != widget.item.id) {
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
    final url = await HomeFeedService.resolveDisplayUrl(
      widget.item.storagePath,
      mimeType: widget.item.mimeType,
      fileName: widget.item.fileName,
    );
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
    final title = widget.item.title.isNotEmpty
        ? widget.item.title
        : widget.item.fileName ?? 'Media';
    switch (widget.item.contentType) {
      case HomeFeedContentType.image:
        await ChatMediaViewer.openImage(context, _url!);
      case HomeFeedContentType.video:
        await ChatMediaViewer.openVideo(context, _url!);
      case HomeFeedContentType.document:
        await StorageFileActions.open(
          context,
          storagePath: widget.item.storagePath,
          title: title,
        );
      default:
        break;
    }
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

    final isImage = item.contentType == HomeFeedContentType.image;
    final card = Material(
      color: isDark ? DriftProTheme.cardDark : DriftProTheme.cardLight,
      elevation: layout.fullPageHero ? 0 : 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Bilder: pinch zoomer på plass; trykk håndteres i PinchZoomInPlace.
        onTap: !widget.interactive || isImage
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
            if (_contentAttachments.isNotEmpty) _buildAttachmentsStrip(),
          ],
        ),
      ),
    );

    return card;
  }

  List<HomeFeedAttachment> get _contentAttachments =>
      widget.item.contentConfig.attachments
          .where((a) => a.storagePath.isNotEmpty)
          .toList();

  Widget _buildAttachmentsStrip() {
    final attachments = _contentAttachments;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
      child: SizedBox(
        height: 72,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: attachments.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final a = attachments[index];
            return _AttachmentThumb(
              attachment: a,
              interactive: widget.interactive,
            );
          },
        ),
      ),
    );
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
        Widget buildImage(BuildContext context) => Image.network(
              url,
              fit: fit,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) =>
                  const Center(child: Icon(Icons.broken_image_outlined)),
            );
        if (!widget.interactive) return buildImage(context);
        return PinchZoomInPlace(
          onTap: _openMedia,
          builder: buildImage,
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

class _AttachmentThumb extends StatefulWidget {
  const _AttachmentThumb({
    required this.attachment,
    required this.interactive,
  });

  final HomeFeedAttachment attachment;
  final bool interactive;

  @override
  State<_AttachmentThumb> createState() => _AttachmentThumbState();
}

class _AttachmentThumbState extends State<_AttachmentThumb> {
  String? _url;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final url = await HomeFeedService.resolveDisplayUrl(
      widget.attachment.storagePath,
      mimeType: widget.attachment.mimeType,
      fileName: widget.attachment.fileName,
    );
    if (mounted) setState(() => _url = url);
  }

  Future<void> _open() async {
    if (!widget.interactive || _url == null) return;
    if (widget.attachment.isVideo) {
      await ChatMediaViewer.openVideo(context, _url!);
    } else if (widget.attachment.isDocument) {
      await StorageFileActions.open(
        context,
        storagePath: widget.attachment.storagePath,
        title: widget.attachment.fileName ?? 'Dokument',
      );
    } else {
      await ChatMediaViewer.openImage(context, _url!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black12,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.interactive &&
                !(widget.attachment.isImage && _url != null)
            ? _open
            : null,
        child: SizedBox(
          width: 96,
          height: 72,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_url != null && widget.attachment.isImage)
                widget.interactive
                    ? PinchZoomInPlace(
                        onTap: _open,
                        builder: (_) =>
                            Image.network(_url!, fit: BoxFit.cover),
                      )
                    : Image.network(_url!, fit: BoxFit.cover)
              else
                Center(
                  child: Icon(
                    widget.attachment.isVideo
                        ? Icons.videocam_outlined
                        : widget.attachment.isDocument
                            ? Icons.description_outlined
                            : Icons.image_outlined,
                    color: DriftProTheme.primaryGreen,
                  ),
                ),
              if (widget.attachment.isVideo)
                const Center(
                  child: Icon(Icons.play_circle_fill, color: Colors.white70),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
