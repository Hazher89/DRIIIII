import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/home_feed_content_config.dart';
import '../../models/home_feed_item.dart';
import '../../models/home_feed_layout_config.dart';
import 'home_feed_block_view.dart';

/// Kombinert forhåndsvisning + størrelse — dra i hver ramme for app/web.
class HomeFeedInteractivePreview extends StatelessWidget {
  const HomeFeedInteractivePreview({
    super.key,
    required this.item,
    required this.layout,
    required this.onLayoutChanged,
    this.onContentChanged,
    this.showToolbar = true,
  });

  final HomeFeedItem item;
  final HomeFeedLayoutConfig layout;
  final ValueChanged<HomeFeedLayoutConfig> onLayoutChanged;
  final ValueChanged<HomeFeedContentConfig>? onContentChanged;
  final bool showToolbar;

  bool get _isSpacer => item.contentType == HomeFeedContentType.spacer;

  double _minHeight({required bool isWeb}) =>
      _isSpacer ? 8 : 80;

  double _maxHeight({required bool isWeb}) =>
      _isSpacer ? (isWeb ? 160 : 120) : 720;

  void _setHeight({required bool isWeb, required double height}) {
    final clamped = height.clamp(_minHeight(isWeb: isWeb), _maxHeight(isWeb: isWeb));
    if (_isSpacer) {
      final spacer = item.contentConfig.spacer;
      onContentChanged?.call(
        item.contentConfig.copyWith(
          spacer: HomeFeedSpacerConfig(
            heightApp: isWeb ? spacer.heightApp : clamped,
            heightWeb: isWeb ? clamped : spacer.heightWeb,
          ),
        ),
      );
      return;
    }
    onLayoutChanged(
      layout.copyWith(
        customHeightApp: isWeb ? layout.customHeightApp : clamped,
        customHeightWeb: isWeb ? clamped : layout.customHeightWeb,
      ),
    );
  }

  double _resolveHeight({required bool isWeb}) {
    if (_isSpacer) {
      final spacer = item.contentConfig.spacer;
      return isWeb ? spacer.heightWeb : spacer.heightApp;
    }
    return layout.resolveHeight(isWeb: isWeb, compactPreview: false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Hold og dra nederst på hver forhåndsvisning for å sette høyde. '
          'App og web lagres separat — slik vises innholdet for brukerne.',
          style: DriftProTheme.bodySm.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        _DualResizeFrames(
          item: item,
          layout: layout,
          isSpacer: _isSpacer,
          appHeight: _resolveHeight(isWeb: false),
          webHeight: _resolveHeight(isWeb: true),
          appMinHeight: _minHeight(isWeb: false),
          appMaxHeight: _maxHeight(isWeb: false),
          webMinHeight: _minHeight(isWeb: true),
          webMaxHeight: _maxHeight(isWeb: true),
          onAppHeight: (h) => _setHeight(isWeb: false, height: h),
          onWebHeight: (h) => _setHeight(isWeb: true, height: h),
        ),
        if (showToolbar && !_isSpacer) ...[
          const SizedBox(height: 20),
          HomeFeedLayoutToolbar(
            layout: layout,
            onLayoutChanged: onLayoutChanged,
          ),
        ],
      ],
    );
  }
}

/// Felles verktøylinje for format, hjørner og hurtigvalg.
class HomeFeedLayoutToolbar extends StatelessWidget {
  const HomeFeedLayoutToolbar({
    super.key,
    required this.layout,
    required this.onLayoutChanged,
  });

  final HomeFeedLayoutConfig layout;
  final ValueChanged<HomeFeedLayoutConfig> onLayoutChanged;

  @override
  Widget build(BuildContext context) {
    final appH = layout.resolveHeight(isWeb: false, compactPreview: false);
    final webH = layout.resolveHeight(isWeb: true, compactPreview: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Format & størrelse', style: DriftProTheme.labelLg),
            ),
            Text(
              'App ${appH.round()} px · Web ${webH.round()} px',
              style: DriftProTheme.bodySm.copyWith(color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: HomeFeedSizePreset.values.map((preset) {
            return ChoiceChip(
              label: Text(preset.label),
              selected: layout.sizePreset == preset &&
                  layout.customHeightApp == null &&
                  layout.customHeightWeb == null,
              onSelected: (_) => onLayoutChanged(
                layout.copyWith(
                  sizePreset: preset,
                  clearCustomHeightApp: true,
                  clearCustomHeightWeb: true,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Hero — dekker mesteparten'),
          value: layout.fullPageHero,
          onChanged: (v) => onLayoutChanged(layout.copyWith(fullPageHero: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Kant-til-kant'),
          value: layout.edgeToEdge,
          onChanged: (v) => onLayoutChanged(layout.copyWith(edgeToEdge: v)),
        ),
        const SizedBox(height: 8),
        Text('Media-tilpasning', style: DriftProTheme.labelMd),
        const SizedBox(height: 6),
        SegmentedButton<HomeFeedMediaFit>(
          segments: HomeFeedMediaFit.values
              .map((f) => ButtonSegment(value: f, label: Text(f.label)))
              .toList(),
          selected: {layout.mediaFit},
          onSelectionChanged: (s) =>
              onLayoutChanged(layout.copyWith(mediaFit: s.first)),
        ),
        const SizedBox(height: 12),
        Text('Hjørner: ${layout.borderRadius.round()} px',
            style: DriftProTheme.labelMd),
        Slider(
          value: layout.borderRadius.clamp(0, 32),
          min: 0,
          max: 32,
          divisions: 32,
          onChanged: (v) => onLayoutChanged(layout.copyWith(borderRadius: v)),
        ),
      ],
    );
  }
}

class _DualResizeFrames extends StatelessWidget {
  const _DualResizeFrames({
    required this.item,
    required this.layout,
    required this.isSpacer,
    required this.appHeight,
    required this.webHeight,
    required this.appMinHeight,
    required this.appMaxHeight,
    required this.webMinHeight,
    required this.webMaxHeight,
    required this.onAppHeight,
    required this.onWebHeight,
  });

  final HomeFeedItem item;
  final HomeFeedLayoutConfig layout;
  final bool isSpacer;
  final double appHeight;
  final double webHeight;
  final double appMinHeight;
  final double appMaxHeight;
  final double webMinHeight;
  final double webMaxHeight;
  final ValueChanged<double> onAppHeight;
  final ValueChanged<double> onWebHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= 720;
        final previewItem = item.copyWith(layoutConfig: layout);
        final frames = [
          _ResizablePreviewFrame(
            label: 'App (mobil)',
            icon: Icons.phone_iphone,
            isWeb: false,
            height: appHeight,
            minHeight: appMinHeight,
            maxHeight: appMaxHeight,
            width: sideBySide ? null : double.infinity,
            onHeightChanged: onAppHeight,
            child: HomeFeedBlockView(
              item: previewItem,
              previewPlatform: HomeFeedPreviewPlatform.app,
              compactPreview: !sideBySide,
              interactive: false,
            ),
          ),
          _ResizablePreviewFrame(
            label: 'Web',
            icon: Icons.laptop_mac,
            isWeb: true,
            height: webHeight,
            minHeight: webMinHeight,
            maxHeight: webMaxHeight,
            width: sideBySide ? null : double.infinity,
            onHeightChanged: onWebHeight,
            child: HomeFeedBlockView(
              item: previewItem,
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
              Expanded(child: frames[0]),
              const SizedBox(width: 12),
              Expanded(child: frames[1]),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            frames[0],
            const SizedBox(height: 12),
            frames[1],
          ],
        );
      },
    );
  }
}

class _ResizablePreviewFrame extends StatefulWidget {
  const _ResizablePreviewFrame({
    required this.label,
    required this.icon,
    required this.isWeb,
    required this.height,
    required this.minHeight,
    required this.maxHeight,
    required this.onHeightChanged,
    required this.child,
    this.width,
  });

  final String label;
  final IconData icon;
  final bool isWeb;
  final double height;
  final double minHeight;
  final double maxHeight;
  final ValueChanged<double> onHeightChanged;
  final Widget child;
  final double? width;

  @override
  State<_ResizablePreviewFrame> createState() => _ResizablePreviewFrameState();
}

class _ResizablePreviewFrameState extends State<_ResizablePreviewFrame> {
  double? _dragHeight;
  bool _dragging = false;

  double get _displayHeight =>
      (_dragHeight ?? widget.height).clamp(widget.minHeight, widget.maxHeight);

  @override
  void didUpdateWidget(covariant _ResizablePreviewFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.height != widget.height) {
      _dragHeight = null;
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final next = (_displayHeight + details.delta.dy)
        .clamp(widget.minHeight, widget.maxHeight);
    setState(() {
      _dragging = true;
      _dragHeight = next;
    });
    widget.onHeightChanged(next);
  }

  void _onDragEnd(DragEndDetails details) {
    setState(() {
      _dragging = false;
      _dragHeight = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = _dragging
        ? DriftProTheme.primaryGreen
        : (isDark ? DriftProTheme.dividerDark : DriftProTheme.dividerLight);

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : DriftProTheme.cardLight,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(color: borderColor, width: _dragging ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Icon(widget.icon, size: 18, color: DriftProTheme.primaryGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: DriftProTheme.labelMd
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${_displayHeight.round()} px høyde',
                        style: DriftProTheme.bodySm.copyWith(
                          color: _dragging
                              ? DriftProTheme.primaryGreen
                              : (isDark ? Colors.white54 : Colors.grey),
                          fontWeight:
                              _dragging ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_dragging)
                  const Icon(Icons.unfold_more, size: 18, color: DriftProTheme.primaryGreen),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: widget.child,
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: 32,
                margin: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                decoration: BoxDecoration(
                  color: _dragging
                      ? DriftProTheme.primaryGreen.withValues(alpha: 0.18)
                      : DriftProTheme.primaryGreen.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: DriftProTheme.primaryGreen.withValues(
                      alpha: _dragging ? 0.6 : 0.25,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.drag_handle_rounded,
                      size: 20,
                      color: DriftProTheme.primaryGreen.withValues(
                        alpha: _dragging ? 1 : 0.7,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Dra for høyde',
                      style: DriftProTheme.bodySm.copyWith(
                        color: DriftProTheme.primaryGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
