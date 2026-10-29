import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// PDF-visning: musehjul/trackpad scroller, knipe + knapper zoomer.
class PlatformPdfBytesView extends StatefulWidget {
  const PlatformPdfBytesView({
    super.key,
    required this.bytes,
    this.fileName,
  });

  final Uint8List bytes;
  final String? fileName;

  @override
  State<PlatformPdfBytesView> createState() => _PlatformPdfBytesViewState();
}

class _PlatformPdfBytesViewState extends State<PlatformPdfBytesView> {
  final _transform = TransformationController();
  final List<Uint8List> _pages = [];
  bool _loading = true;
  String? _error;
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    _raster();
  }

  @override
  void didUpdateWidget(covariant PlatformPdfBytesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes) {
      _pages.clear();
      _loading = true;
      _error = null;
      _raster();
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _raster() async {
    try {
      final out = <Uint8List>[];
      await for (final page in Printing.raster(widget.bytes, dpi: 140)) {
        out.add(await page.toPng());
        if (!mounted) return;
        setState(() {
          _pages
            ..clear()
            ..addAll(out);
          _loading = false;
        });
      }
      if (!mounted) return;
      setState(() {
        _pages
          ..clear()
          ..addAll(out);
        _loading = false;
        if (out.isEmpty) _error = 'PDF har ingen sider.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Kunne ikke vise PDF: $e';
      });
    }
  }

  void _setScale(double next) {
    final clamped = next.clamp(0.6, 5.0);
    final focal = Offset(
      MediaQuery.sizeOf(context).width / 2,
      MediaQuery.sizeOf(context).height / 3,
    );
    final sceneFocal = _transform.toScene(focal);
    final m = Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(clamped, clamped, clamped, 1)
      ..translateByDouble(-sceneFocal.dx, -sceneFocal.dy, 0, 1);
    _transform.value = m;
    setState(() => _scale = clamped);
  }

  void _zoomIn() => _setScale(_scale + 0.35);
  void _zoomOut() => _setScale(_scale - 0.35);

  /// Musehjul zoomer ellers i [InteractiveViewer] — stjel signalet og pan i stedet.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // Trackpad: InteractiveViewer pan'er allerede (trackpadScrollCausesScale=false).
    if (event.kind == PointerDeviceKind.trackpad) return;

    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final scroll = e as PointerScrollEvent;
      final local = scroll.localPosition;
      final focalPointScene = _transform.toScene(local);
      final newFocalPointScene =
          _transform.toScene(local - scroll.scrollDelta);
      final next = Matrix4.copy(_transform.value)
        ..translateByDouble(
          newFocalPointScene.dx - focalPointScene.dx,
          newFocalPointScene.dy - focalPointScene.dy,
          0,
          1,
        );
      _transform.value = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _pages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Laster PDF…'),
          ],
        ),
      );
    }
    if (_error != null && _pages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final pageWidth = (width - 16).clamp(280.0, 1200.0);

    return Stack(
      children: [
        ColoredBox(
          color: const Color(0xFFF4F7F5),
          child: Listener(
            onPointerSignal: _onPointerSignal,
            child: InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(120),
              minScale: 0.6,
              maxScale: 5,
              // Scroll = pan (ikke zoom). Zoom via knipe eller +/- knapper.
              trackpadScrollCausesScale: false,
              scaleEnabled: true,
              panEnabled: true,
              onInteractionUpdate: (_) {
                final s = _transform.value.getMaxScaleOnAxis();
                if ((s - _scale).abs() > 0.01) {
                  setState(() => _scale = s);
                }
              },
              child: SizedBox(
                width: pageWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _pages.length; i++)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                        child: Material(
                          color: Colors.white,
                          elevation: 1.5,
                          borderRadius: BorderRadius.circular(4),
                          clipBehavior: Clip.antiAlias,
                          child: Image.memory(
                            _pages[i],
                            width: pageWidth - 16,
                            fit: BoxFit.fitWidth,
                            filterQuality: FilterQuality.medium,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ZoomFab(
                tooltip: 'Zoom inn',
                icon: Icons.add,
                onPressed: _scale >= 4.9 ? null : _zoomIn,
              ),
              const SizedBox(height: 8),
              _ZoomFab(
                tooltip: 'Zoom ut',
                icon: Icons.remove,
                onPressed: _scale <= 0.65 ? null : _zoomOut,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ZoomFab extends StatelessWidget {
  const _ZoomFab({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      color: Colors.white,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: const Color(0xFF1B5E20)),
      ),
    );
  }
}
