import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/vision/vision_camera_service.dart';

/// Live-visning på web: poller worker direkte (ingen iframe).
Widget buildUniformLiveEmbed({VoidCallback? onReady}) {
  return WebLivePoll(onReady: onReady);
}

class WebLivePoll extends StatefulWidget {
  const WebLivePoll({super.key, this.onReady});

  final VoidCallback? onReady;

  @override
  State<WebLivePoll> createState() => _WebLivePollState();
}

class _WebLivePollState extends State<WebLivePoll> {
  Timer? _timer;
  int _tick = 0;
  bool _ready = false;
  int _errors = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 180), (_) {
      if (!mounted) return;
      setState(() => _tick++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onImage(Object? _, StackTrace? __) {
    _errors++;
    if (_errors > 8 && mounted) setState(() {});
  }

  void _onImageOk() {
    if (!_ready) {
      _ready = true;
      _errors = 0;
      widget.onReady?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_errors > 8) {
      return _WorkerOfflineMessage(scheme: scheme);
    }
    final url =
        '${VisionCameraService.localWorkerLiveUrl}?$_tick';
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, wasSyncLoaded) {
        if (frame != null) _onImageOk();
        if (wasSyncLoaded) _onImageOk();
        return child;
      },
      errorBuilder: (context, error, stackTrace) {
        _onImage(error, stackTrace);
        return ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

class _WorkerOfflineMessage extends StatelessWidget {
  const _WorkerOfflineMessage({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.videocam_off_outlined,
                size: 48,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'Kamera-stream ikke tilgjengelig',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Start vision worker:\ncd services/vision_monitor && ./run.sh',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
