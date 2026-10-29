import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// PDF-visning: musehjul/trackpad scroller sidene.
/// Zoom kun via +/- (ikke musehjul).
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
  final _scroll = ScrollController();
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
    _scroll.dispose();
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

  void _zoomIn() => setState(() => _scale = (_scale + 0.25).clamp(0.6, 3.0));
  void _zoomOut() => setState(() => _scale = (_scale - 0.25).clamp(0.6, 3.0));

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

    final viewportW = MediaQuery.sizeOf(context).width;
    final basePageW = (viewportW - 16).clamp(280.0, 1200.0);
    final pageW = basePageW * _scale;

    return Stack(
      children: [
        ColoredBox(
          color: const Color(0xFFF4F7F5),
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scroll,
              // Eksplisitt: musehjul skal scrolle, aldri zoome.
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: pageW + 16,
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
                              width: pageW,
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
                      const SizedBox(height: 72),
                    ],
                  ),
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
                onPressed: _scale >= 2.95 ? null : _zoomIn,
              ),
              const SizedBox(height: 8),
              Material(
                elevation: 3,
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    '${(_scale * 100).round()}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: Color(0xFF1B5E20),
                    ),
                  ),
                ),
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
