import 'package:flutter/material.dart';

import '../../../core/services/vision/vision_camera_service.dart';

/// Live feed over kamera — grønn OK, rød avvik, lyseblå skanning.
class UniformLiveFeedOverlay extends StatefulWidget {
  const UniformLiveFeedOverlay({
    super.key,
    required this.lines,
    required this.persons,
    required this.scanActive,
  });

  final List<VisionFeedLine> lines;
  final int persons;
  final bool scanActive;

  @override
  State<UniformLiveFeedOverlay> createState() => _UniformLiveFeedOverlayState();
}

class _UniformLiveFeedOverlayState extends State<UniformLiveFeedOverlay>
    with TickerProviderStateMixin {
  final Set<String> _seen = {};
  final List<_FloatingLine> _active = [];
  String _statusLine = 'Skanner live etter MAVI-logo og vernesko…';

  static const _okColor = Color(0xFF66BB6A);
  static const _badColor = Color(0xFFEF5350);
  static const _scanColor = Color(0xFF81D4FA);

  @override
  void didUpdateWidget(UniformLiveFeedOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.persons > 0) {
      _statusLine = widget.persons == 1
          ? '1 person i bildet — analyserer uniform'
          : '${widget.persons} personer i bildet — analyserer uniform';
    } else if (widget.scanActive) {
      _statusLine = 'Skanner live etter MAVI-logo og vernesko…';
    }

    for (final line in widget.lines) {
      if (line.id.isEmpty || !_seen.add(line.id)) continue;
      _statusLine = line.text;
      _spawn(line);
    }
  }

  void _spawn(VisionFeedLine line) {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    );
    final entry = _FloatingLine(line: line, controller: controller);
    setState(() => _active.add(entry));
    if (_active.length > 6) {
      final old = _active.removeAt(0);
      old.controller.dispose();
    }
    controller.forward().whenComplete(() {
      if (!mounted) return;
      setState(() => _active.remove(entry));
      controller.dispose();
    });
  }

  @override
  void dispose() {
    for (final entry in _active) {
      entry.controller.dispose();
    }
    super.dispose();
  }

  Color _colorFor(VisionFeedLine line) {
    if (line.isOk) return _okColor;
    if (line.isViolation) return _badColor;
    return _scanColor;
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = widget.persons > 0 ? _scanColor : Colors.white70;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Fast statuslinje — alltid synlig
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: statusColor.withValues(alpha: 0.6)),
              ),
              child: Text(
                _statusLine,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ),
          ),
          // Flytende meldinger oppover
          for (var i = 0; i < _active.length; i++)
            Positioned(
              left: 10,
              right: 10,
              bottom: 52 + (i % 3) * 8.0,
              child: _FloatingBubble(
                entry: _active[i],
                color: _colorFor(_active[i].line),
              ),
            ),
        ],
      ),
    );
  }
}

class _FloatingLine {
  _FloatingLine({required this.line, required this.controller});

  final VisionFeedLine line;
  final AnimationController controller;
}

class _FloatingBubble extends StatelessWidget {
  const _FloatingBubble({required this.entry, required this.color});

  final _FloatingLine entry;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final line = entry.line;
    final label = line.trackId != null ? 'Person ${line.trackId}' : 'Live';

    return AnimatedBuilder(
      animation: entry.controller,
      builder: (context, child) {
        final t = Curves.easeOut.transform(entry.controller.value);
        return Opacity(
          opacity: (1.0 - t).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -140 * t),
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Text(
          '$label · ${line.text}',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 13,
            height: 1.25,
          ),
        ),
      ),
    );
  }
}
