import 'package:flutter/material.dart';

import '../core/constants/driftpro_brand.dart';

/// Roterende D-ikon fra DriftPro-logoen — erstatter standardsirkel ved lasting.
class DriftProLoadingIndicator extends StatefulWidget {
  const DriftProLoadingIndicator({
    super.key,
    this.size = 40,
    this.duration = const Duration(milliseconds: 1100),
  });

  final double size;
  final Duration duration;

  @override
  State<DriftProLoadingIndicator> createState() => _DriftProLoadingIndicatorState();
}

class _DriftProLoadingIndicatorState extends State<DriftProLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)..repeat();
  }

  @override
  void didUpdateWidget(covariant DriftProLoadingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller
        ..duration = widget.duration
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Image.asset(
        DriftProBrand.logoIcon,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

/// Fullside lasting med sentrert DriftPro-spinner.
class DriftProLoadingCenter extends StatelessWidget {
  const DriftProLoadingCenter({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(child: DriftProLoadingIndicator(size: size));
  }
}
