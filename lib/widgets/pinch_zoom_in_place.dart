import 'package:flutter/material.dart';

/// Pinch/zoom inne i rammen uten å åpne fullskjerm.
/// Ett trykk kaller [onTap] (f.eks. åpne bildevisning).
class PinchZoomInPlace extends StatefulWidget {
  const PinchZoomInPlace({
    super.key,
    required this.child,
    this.onTap,
    this.minScale = 1,
    this.maxScale = 5,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double minScale;
  final double maxScale;

  @override
  State<PinchZoomInPlace> createState() => _PinchZoomInPlaceState();
}

class _PinchZoomInPlaceState extends State<PinchZoomInPlace>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _resetAnim;
  Animation<Matrix4>? _resetTween;
  int _pointers = 0;
  bool _pinching = false;

  bool get _zoomed => _transform.value.getMaxScaleOnAxis() > 1.02;

  @override
  void initState() {
    super.initState();
    _resetAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        final t = _resetTween;
        if (t != null) _transform.value = t.value;
      });
    _transform.addListener(_onTransform);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _resetAnim.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _onTransform() {
    if (mounted) setState(() {});
  }

  void _animateReset() {
    _resetTween = Matrix4Tween(
      begin: _transform.value,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(parent: _resetAnim, curve: Curves.easeOutCubic));
    _resetAnim
      ..reset()
      ..forward();
  }

  void _handleTap() {
    if (_zoomed) {
      _animateReset();
      return;
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        _pointers++;
        if (_pointers >= 2) {
          setState(() => _pinching = true);
          _resetAnim.stop();
        }
      },
      onPointerUp: (_) {
        _pointers = (_pointers - 1).clamp(0, 10);
        if (_pointers < 2 && _pinching) {
          setState(() => _pinching = false);
        }
      },
      onPointerCancel: (_) {
        _pointers = 0;
        if (_pinching) setState(() => _pinching = false);
      },
      child: InteractiveViewer(
          transformationController: _transform,
          minScale: widget.minScale,
          maxScale: widget.maxScale,
          // Pan kun når zoomet — ellers kan lista scrolle normalt.
          panEnabled: _zoomed || _pinching,
          scaleEnabled: true,
          clipBehavior: Clip.hardEdge,
          boundaryMargin: _zoomed
              ? const EdgeInsets.all(48)
              : EdgeInsets.zero,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleTap,
            onDoubleTap: _animateReset,
            child: SizedBox.expand(child: widget.child),
          ),
        ),
    );
  }
}
