import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants/driftpro_brand.dart';

/// Roterende merke for små loaders (knapper, lister).
class DriftProLoadingIndicator extends StatefulWidget {
  const DriftProLoadingIndicator({
    super.key,
    this.size = 40,
    this.duration = const Duration(milliseconds: 1100),
  });

  final double size;
  final Duration duration;

  @override
  State<DriftProLoadingIndicator> createState() =>
      _DriftProLoadingIndicatorState();
}

class _DriftProLoadingIndicatorState extends State<DriftProLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: widget.duration)..repeat();
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

/// Sentrert liten spinner.
class DriftProLoadingCenter extends StatelessWidget {
  const DriftProLoadingCenter({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(child: DriftProLoadingIndicator(size: size));
  }
}

/// Fullside oppstart/ lasting — sort flate + neon-merke (matcher iOS LaunchScreen).
class DriftProLoadingPage extends StatelessWidget {
  const DriftProLoadingPage({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Image.asset(
            DriftProBrand.splashMark,
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}
