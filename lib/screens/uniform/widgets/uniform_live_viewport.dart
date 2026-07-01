import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../models/vision_camera.dart';
import '../../../core/services/vision/vision_camera_service.dart';
import 'uniform_live_embed.dart';
import 'uniform_live_feed_overlay.dart';

/// Ren live-visning: kun kamera + profesjonelle overlays.
class UniformLiveViewport extends StatefulWidget {
  const UniformLiveViewport({
    super.key,
    required this.cameras,
    required this.activeCameraId,
    required this.liveFrame,
    required this.liveError,
    required this.scanPersons,
    required this.scanActive,
    required this.sessionViolations,
    required this.feedLines,
    required this.onCameraSelected,
    required this.onRetry,
    this.onStreamReady,
  });

  final List<VisionCamera> cameras;
  final String? activeCameraId;
  final Uint8List? liveFrame;
  final String? liveError;
  final int scanPersons;
  final bool scanActive;
  final int sessionViolations;
  final List<VisionFeedLine> feedLines;
  final ValueChanged<String> onCameraSelected;
  final VoidCallback onRetry;
  final VoidCallback? onStreamReady;

  @override
  State<UniformLiveViewport> createState() => _UniformLiveViewportState();
}

class _UniformLiveViewportState extends State<UniformLiveViewport>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String? get _cameraName {
    if (widget.cameras.isEmpty || widget.activeCameraId == null) return null;
    return widget.cameras
        .firstWhere(
          (c) => c.id == widget.activeCameraId,
          orElse: () => widget.cameras.first,
        )
        .name;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.cameras.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.cameras.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final cam = widget.cameras[i];
                  final selected = cam.id == widget.activeCameraId;
                  return ChoiceChip(
                    label: Text(cam.name),
                    selected: selected,
                    onSelected: (_) => widget.onCameraSelected(cam.id),
                  );
                },
              ),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      _LiveBadge(pulse: _pulse),
                      const Spacer(),
                      if (_cameraName != null)
                        _GlassChip(
                          icon: Icons.videocam_outlined,
                          label: _cameraName!,
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (kIsWeb)
                          buildUniformLiveEmbed(
                            onReady: widget.onStreamReady,
                          )
                        else
                          _NativeLiveFeed(
                            liveFrame: widget.liveFrame,
                            liveError: widget.liveError,
                            camerasEmpty: widget.cameras.isEmpty,
                            pulse: _pulse,
                            scanActive: widget.scanActive,
                            onRetry: widget.onRetry,
                          ),
                        if (widget.scanActive)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedBuilder(
                                animation: _pulse,
                                builder: (context, _) {
                                  return CustomPaint(
                                    painter: _ScanFramePainter(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(
                                            alpha:
                                                0.2 + _pulse.value * 0.3,
                                          ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        Positioned.fill(
                          child: UniformLiveFeedOverlay(
                            lines: widget.feedLines,
                            persons: widget.scanPersons,
                            scanActive: widget.scanActive || kIsWeb,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _ScanStatusBar(
                  pulse: _pulse,
                  active: widget.scanActive || kIsWeb,
                  persons: widget.scanPersons,
                  violations: widget.sessionViolations,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NativeLiveFeed extends StatelessWidget {
  const _NativeLiveFeed({
    required this.liveFrame,
    required this.liveError,
    required this.camerasEmpty,
    required this.pulse,
    required this.scanActive,
    required this.onRetry,
  });

  final Uint8List? liveFrame;
  final String? liveError;
  final bool camerasEmpty;
  final Animation<double> pulse;
  final bool scanActive;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: scheme.surfaceContainerHighest),
        if (liveFrame != null)
          Image.memory(
            liveFrame!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          )
        else
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  camerasEmpty
                      ? 'Ingen kamera — trykk ⚙ for oppsett'
                      : _friendlyError(liveError) ?? 'Kobler til kamera…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                if (liveError != null) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Prøv igjen'),
                  ),
                ],
              ],
            ),
          ),
        if (scanActive && liveFrame != null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: pulse,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _ScanFramePainter(
                      color: scheme.primary.withValues(
                        alpha: 0.25 + pulse.value * 0.35,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  static String? _friendlyError(String? raw) {
    if (raw == null) return null;
    if (raw.contains('8090') || raw.contains('worker')) {
      return 'Kamera-stream ikke tilgjengelig.\nStart vision worker lokalt.';
    }
    if (raw.contains('vision-camera') || raw.contains('404')) {
      return 'Kobler til kamera…';
    }
    return 'Kobler til kamera…';
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.lerp(
                    const Color(0xFFE53935),
                    const Color(0xFFFF8A80),
                    pulse.value,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'LIVE',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: scheme.onSurface, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ScanStatusBar extends StatelessWidget {
  const _ScanStatusBar({
    required this.pulse,
    required this.active,
    required this.persons,
    required this.violations,
  });

  final Animation<double> pulse;
  final bool active;
  final int persons;
  final int violations;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.primary.withValues(alpha: 0.35 + pulse.value * 0.25),
            ),
          ),
          child: Row(
            children: [
              Icon(
                active ? Icons.radar_outlined : Icons.hourglass_empty,
                color: active ? scheme.primary : scheme.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  active
                      ? 'Skanner etter MAVI-logo og vernesko'
                      : 'Venter på kamerastrøm…',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              if (active) ...[
                _StatPill(
                  label: persons == 1 ? '1 person' : '$persons personer',
                  icon: Icons.person_outline,
                ),
                const SizedBox(width: 6),
                _StatPill(
                  label: '$violations brudd',
                  icon: Icons.warning_amber_rounded,
                  warn: violations > 0,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.icon,
    this.warn = false,
  });

  final String label;
  final IconData icon;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = warn ? scheme.error : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: warn
            ? scheme.errorContainer.withValues(alpha: 0.45)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  _ScanFramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const inset = 10.0;
    const corner = 28.0;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2),
      const Radius.circular(4),
    );
    canvas.drawRRect(r, paint);

    void cornerLine(Offset start, Offset end) {
      canvas.drawLine(start, end, paint..strokeWidth = 3);
    }

    final w = size.width;
    final h = size.height;
    cornerLine(Offset(inset, inset + corner), Offset(inset, inset));
    cornerLine(Offset(inset, inset), Offset(inset + corner, inset));
    cornerLine(Offset(w - inset - corner, inset), Offset(w - inset, inset));
    cornerLine(Offset(w - inset, inset), Offset(w - inset, inset + corner));
    cornerLine(Offset(inset, h - inset - corner), Offset(inset, h - inset));
    cornerLine(Offset(inset, h - inset), Offset(inset + corner, h - inset));
    cornerLine(Offset(w - inset - corner, h - inset), Offset(w - inset, h - inset));
    cornerLine(Offset(w - inset, h - inset - corner), Offset(w - inset, h - inset));
  }

  @override
  bool shouldRepaint(covariant _ScanFramePainter oldDelegate) =>
      oldDelegate.color != color;
}
