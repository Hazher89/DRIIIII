import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/home_feed_content_config.dart';
import '../../models/home_feed_item.dart';
import '../../models/home_feed_layout_config.dart';
import 'home_feed_block_view.dart';

/// Realistisk iPhone-ramme med live forside og dra-for-å-omorganisere.
class HomeFeedIphonePreview extends StatefulWidget {
  const HomeFeedIphonePreview({
    super.key,
    required this.editingItem,
    required this.feedItems,
    required this.layout,
    required this.asWeb,
    required this.onAsWebChanged,
    required this.onLayoutChanged,
    required this.onContentChanged,
    required this.onReorder,
  });

  final HomeFeedItem editingItem;
  final List<HomeFeedItem> feedItems;
  final HomeFeedLayoutConfig layout;
  final bool asWeb;
  final ValueChanged<bool> onAsWebChanged;
  final ValueChanged<HomeFeedLayoutConfig> onLayoutChanged;
  final ValueChanged<HomeFeedContentConfig> onContentChanged;
  final Future<void> Function(List<HomeFeedItem> ordered) onReorder;

  @override
  State<HomeFeedIphonePreview> createState() => _HomeFeedIphonePreviewState();
}

class _HomeFeedIphonePreviewState extends State<HomeFeedIphonePreview> {
  double? _dragHeight;
  bool _dragging = false;

  bool get _isSpacer =>
      widget.editingItem.contentType == HomeFeedContentType.spacer;

  double get _minH => _isSpacer ? 8 : 80;
  double get _maxH => _isSpacer ? 120 : 720;

  double get _baseHeight {
    if (_isSpacer) {
      return widget.asWeb
          ? widget.editingItem.contentConfig.spacer.heightWeb
          : widget.editingItem.contentConfig.spacer.heightApp;
    }
    return widget.layout.resolveHeight(
      isWeb: widget.asWeb,
      compactPreview: false,
    );
  }

  double get _displayHeight =>
      (_dragHeight ?? _baseHeight).clamp(_minH, _maxH);

  List<HomeFeedItem> get _orderedFeed {
    return widget.feedItems.map((item) {
      if (item.id == widget.editingItem.id) {
        return widget.editingItem.copyWith(layoutConfig: widget.layout);
      }
      return item;
    }).toList();
  }

  void _applyHeight(double height) {
    final clamped = height.clamp(_minH, _maxH);
    if (_isSpacer) {
      final spacer = widget.editingItem.contentConfig.spacer;
      widget.onContentChanged(
        widget.editingItem.contentConfig.copyWith(
          spacer: HomeFeedSpacerConfig(
            heightApp: widget.asWeb ? spacer.heightApp : clamped,
            heightWeb: widget.asWeb ? clamped : spacer.heightWeb,
          ),
        ),
      );
      return;
    }
    widget.onLayoutChanged(
      widget.layout.copyWith(
        customHeightApp:
            widget.asWeb ? widget.layout.customHeightApp : clamped,
        customHeightWeb:
            widget.asWeb ? clamped : widget.layout.customHeightWeb,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant HomeFeedIphonePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging &&
        (oldWidget.layout != widget.layout ||
            oldWidget.asWeb != widget.asWeb ||
            oldWidget.editingItem.contentConfig !=
                widget.editingItem.contentConfig)) {
      _dragHeight = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final feedBg = isDark ? const Color(0xFF0E1114) : const Color(0xFFF7F8FA);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Icon(
                widget.asWeb ? Icons.laptop_mac : Icons.phone_iphone,
                size: 18,
                color: DriftProTheme.primaryGreen,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.asWeb
                      ? 'Web-forhåndsvisning'
                      : 'iPhone — slik det ser ut i appen',
                  style: DriftProTheme.labelMd.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SegmentedButton<bool>(
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(value: false, label: Text('App')),
                  ButtonSegment(value: true, label: Text('Web')),
                ],
                selected: {widget.asWeb},
                onSelectionChanged: (s) => widget.onAsWebChanged(s.first),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Hold og dra for å bytte rekkefølge på innholdet.',
            style: DriftProTheme.bodySm.copyWith(color: Colors.grey[600]),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: AspectRatio(
                aspectRatio: widget.asWeb ? 9 / 14 : 9 / 19.5,
                child: widget.asWeb
                    ? _WebFrame(
                        feedBg: feedBg,
                        child: _feedList(feedBg, isDark),
                      )
                    : _IPhoneFrame(
                        feedBg: feedBg,
                        isDark: isDark,
                        child: _feedList(feedBg, isDark),
                      ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              Text(
                'Høyde på valgt blokk: ${_displayHeight.round()} px',
                style: DriftProTheme.bodySm.copyWith(
                  color: _dragging
                      ? DriftProTheme.primaryGreen
                      : Colors.grey[600],
                  fontWeight: _dragging ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (d) {
                  final next =
                      (_displayHeight + d.delta.dy).clamp(_minH, _maxH);
                  setState(() {
                    _dragging = true;
                    _dragHeight = next;
                  });
                  _applyHeight(next);
                },
                onVerticalDragEnd: (_) => setState(() {
                  _dragging = false;
                  _dragHeight = null;
                }),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: DriftProTheme.primaryGreen.withValues(
                        alpha: _dragging ? 0.2 : 0.1,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: DriftProTheme.primaryGreen.withValues(
                          alpha: _dragging ? 0.7 : 0.3,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.drag_handle_rounded,
                          color: DriftProTheme.primaryGreen,
                          size: 20,
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
        ),
      ],
    );
  }

  Widget _feedList(Color feedBg, bool isDark) {
    final items = _orderedFeed;
    if (items.isEmpty) {
      return ColoredBox(
        color: feedBg,
        child: const Center(
          child: Text('Ingen innhold ennå', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return ColoredBox(
      color: feedBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.asWeb) _statusBar(isDark, feedBg),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Text(
              'Forside',
              style: DriftProTheme.labelLg.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
              itemCount: items.length,
              onReorderItem: (oldIndex, newIndex) async {
                final next = List<HomeFeedItem>.from(items);
                final moved = next.removeAt(oldIndex);
                next.insert(newIndex, moved);
                await widget.onReorder(next);
              },
              proxyDecorator: (child, index, animation) {
                return Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.transparent,
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final item = items[index];
                final selected = item.id == widget.editingItem.id;
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(item.id),
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? DriftProTheme.primaryGreen
                              : Colors.transparent,
                          width: selected ? 2 : 0,
                        ),
                      ),
                      child: HomeFeedBlockView(
                        item: item,
                        previewPlatform: widget.asWeb
                            ? HomeFeedPreviewPlatform.web
                            : HomeFeedPreviewPlatform.app,
                        compactPreview: true,
                        interactive: false,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (!widget.asWeb)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Center(
                child: SizedBox(
                  width: 120,
                  height: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.all(Radius.circular(99)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusBar(bool isDark, Color bg) {
    return Container(
      height: 44,
      color: bg,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 22,
            top: 14,
            child: Text(
              '9:41',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Container(
            width: 96,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          Positioned(
            right: 18,
            top: 14,
            child: Row(
              children: [
                Icon(
                  Icons.signal_cellular_alt,
                  size: 12,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.wifi,
                  size: 12,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.battery_full,
                  size: 12,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IPhoneFrame extends StatelessWidget {
  const _IPhoneFrame({
    required this.feedBg,
    required this.isDark,
    required this.child,
  });

  final Color feedBg;
  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(44),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
        border: Border.all(color: const Color(0xFF3A3A3C), width: 2),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Container(
        decoration: BoxDecoration(
          color: feedBg,
          borderRadius: BorderRadius.circular(36),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.black12,
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

class _WebFrame extends StatelessWidget {
  const _WebFrame({required this.feedBg, required this.child});

  final Color feedBg;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ColoredBox(color: feedBg, child: child),
      ),
    );
  }
}
