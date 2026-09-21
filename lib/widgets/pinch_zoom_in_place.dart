import 'package:flutter/material.dart';

/// Pinch gjør hele bildet fysisk større (via overlay), ikke zoom inne i en klipperamme.
/// Ett trykk kaller [onTap] (f.eks. åpne bildevisning).
class PinchZoomInPlace extends StatefulWidget {
  const PinchZoomInPlace({
    super.key,
    required this.builder,
    this.onTap,
    this.minScale = 1,
    this.maxScale = 4,
  });

  /// Bygges både i lista og i overlay (to separate widgets).
  final WidgetBuilder builder;
  final VoidCallback? onTap;
  final double minScale;
  final double maxScale;

  @override
  State<PinchZoomInPlace> createState() => _PinchZoomInPlaceState();
}

class _PinchZoomInPlaceState extends State<PinchZoomInPlace>
    with SingleTickerProviderStateMixin {
  final GlobalKey _boxKey = GlobalKey();

  OverlayEntry? _overlay;
  Rect? _origin;

  double _scale = 1;
  Offset _pan = Offset.zero;

  double _scaleAtStart = 1;
  Offset _panAtStart = Offset.zero;
  Offset _focalAtStart = Offset.zero;

  bool _lifting = false;

  late final AnimationController _resetCtrl;
  Animation<double>? _scaleAnim;
  Animation<Offset>? _panAnim;

  bool get _enlarged => _scale > 1.02;

  @override
  void initState() {
    super.initState();
    _resetCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        final s = _scaleAnim;
        final p = _panAnim;
        if (s == null || p == null) return;
        _scale = s.value;
        _pan = p.value;
        _overlay?.markNeedsBuild();
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _resetCtrl.dispose();
    _tearDownOverlay();
    super.dispose();
  }

  void _captureOrigin() {
    final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _origin = box.localToGlobal(Offset.zero) & box.size;
  }

  void _ensureOverlay() {
    if (_overlay != null) return;
    _captureOrigin();
    if (_origin == null) return;

    setState(() => _lifting = true);
    _overlay = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context, rootOverlay: true).insert(_overlay!);
  }

  void _tearDownOverlay() {
    _overlay?.remove();
    _overlay = null;
    _origin = null;
    _lifting = false;
  }

  void _removeOverlay() {
    _tearDownOverlay();
    if (mounted) setState(() {});
  }

  Widget _buildOverlay(BuildContext context) {
    final origin = _origin;
    if (origin == null) return const SizedBox.shrink();

    final w = origin.width * _scale;
    final h = origin.height * _scale;
    final left = origin.left + (origin.width - w) / 2 + _pan.dx;
    final top = origin.top + (origin.height - h) / 2 + _pan.dy;
    final dim = ((_scale - 1) / 2.2).clamp(0.0, 0.5);

    return IgnorePointer(
      child: Stack(
        children: [
          if (_enlarged)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: dim),
              ),
            ),
          Positioned(
            left: left,
            top: top,
            width: w,
            height: h,
            child: Material(
              elevation: _enlarged ? 16 : 0,
              shadowColor: Colors.black54,
              color: Colors.transparent,
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(4),
              child: widget.builder(context),
            ),
          ),
        ],
      ),
    );
  }

  void _animateReset() {
    if (!_enlarged && _overlay == null) return;
    _resetCtrl.stop();
    _scaleAnim = Tween<double>(begin: _scale, end: 1).animate(
      CurvedAnimation(parent: _resetCtrl, curve: Curves.easeOutCubic),
    );
    _panAnim = Tween<Offset>(begin: _pan, end: Offset.zero).animate(
      CurvedAnimation(parent: _resetCtrl, curve: Curves.easeOutCubic),
    );
    _resetCtrl.forward(from: 0).whenComplete(() {
      _scale = 1;
      _pan = Offset.zero;
      _removeOverlay();
    });
  }

  void _onTap() {
    if (_enlarged) {
      _animateReset();
      return;
    }
    widget.onTap?.call();
  }

  void _onScaleStart(ScaleStartDetails d) {
    _resetCtrl.stop();
    _scaleAtStart = _scale;
    _panAtStart = _pan;
    _focalAtStart = d.focalPoint;
    if (d.pointerCount >= 2) {
      _ensureOverlay();
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2 && _overlay == null) {
      _ensureOverlay();
    }
    if (_overlay == null) return;

    _scale = (_scaleAtStart * d.scale).clamp(widget.minScale, widget.maxScale);
    _pan = _panAtStart + (d.focalPoint - _focalAtStart);
    _overlay?.markNeedsBuild();
    if (mounted) setState(() {});
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_scale > 1.02) {
      _animateReset();
    } else {
      _scale = 1;
      _pan = Offset.zero;
      _removeOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _boxKey,
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      onDoubleTap: _animateReset,
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: _onScaleEnd,
      child: SizedBox.expand(
        child: Opacity(
          opacity: _lifting ? 0 : 1,
          child: widget.builder(context),
        ),
      ),
    );
  }
}
