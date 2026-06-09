import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'driftpro_living_mark_painter.dart';
import 'driftpro_living_scenes.dart';

enum DriftProIconMotion { ambient, loading }

/// Levende D-merke — én shufflet scene om gangen, kontinuerlig loop.
class DriftProAnimatedIcon extends StatefulWidget {
  const DriftProAnimatedIcon({
    super.key,
    required this.size,
    this.motion = DriftProIconMotion.ambient,
  });

  final double size;
  final DriftProIconMotion motion;

  @override
  State<DriftProAnimatedIcon> createState() => _DriftProAnimatedIconState();
}

class _DriftProAnimatedIconState extends State<DriftProAnimatedIcon>
    with TickerProviderStateMixin {
  static const _sceneDuration = Duration(milliseconds: 3200);

  late final List<DriftProLivingScene> _order;
  late final AnimationController _scene;
  AnimationController? _spin;
  int _orderIndex = 0;
  final _rng = math.Random();

  bool get _loading => widget.motion == DriftProIconMotion.loading;

  @override
  void initState() {
    super.initState();
    _order = _shuffledOrder();
    _scene = AnimationController(vsync: this, duration: _sceneDuration)
      ..addStatusListener(_onSceneStatus);
    _scene.forward();

    if (_loading) {
      _spin = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      )..repeat();
    }
  }

  List<DriftProLivingScene> _shuffledOrder() {
    final list = List<DriftProLivingScene>.from(DriftProLivingScene.values);
    list.shuffle(_rng);
    return list;
  }

  void _onSceneStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {
      _orderIndex = (_orderIndex + 1) % _order.length;
      if (_orderIndex == 0) {
        _order
          ..clear()
          ..addAll(_shuffledOrder());
      }
    });
    _scene.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant DriftProAnimatedIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motion == widget.motion) return;

    if (_loading) {
      _spin ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      )..repeat();
    } else {
      _spin?.dispose();
      _spin = null;
    }
  }

  @override
  void dispose() {
    _scene.removeStatusListener(_onSceneStatus);
    _scene.dispose();
    _spin?.dispose();
    super.dispose();
  }

  double _sceneOpacity(double t) {
    const edge = 0.14;
    if (t < edge) return Curves.easeOut.transform(t / edge);
    if (t > 1 - edge) return Curves.easeIn.transform((1 - t) / edge);
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final living = AnimatedBuilder(
      animation: _scene,
      builder: (context, _) {
        return CustomPaint(
          size: Size.square(widget.size),
          painter: DriftProLivingMarkPainter(
            scene: _order[_orderIndex],
            sceneT: _scene.value,
            sceneOpacity: _sceneOpacity(_scene.value),
            isDark: Theme.of(context).brightness == Brightness.dark,
          ),
        );
      },
    );

    if (!_loading || _spin == null) {
      return SizedBox(width: widget.size, height: widget.size, child: living);
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RotationTransition(turns: _spin!, child: living),
    );
  }
}
