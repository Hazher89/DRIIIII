import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Fullskjerm bilde/video-visning.
class ChatMediaViewer {
  static Future<void> openImage(BuildContext context, String url, {String? heroTag}) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Lukk',
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) => _ImageViewerPage(url: url, heroTag: heroTag),
    );
  }

  static Future<void> openVideo(BuildContext context, String url) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (_) => _VideoViewerSheet(url: url),
    );
  }
}

class _ImageViewerPage extends StatefulWidget {
  const _ImageViewerPage({required this.url, this.heroTag});

  final String url;
  final String? heroTag;

  @override
  State<_ImageViewerPage> createState() => _ImageViewerPageState();
}

/// Pinch skalerer hele bildet (blir større), ikke zoom inne i en klipperamme.
class _ImageViewerPageState extends State<_ImageViewerPage>
    with SingleTickerProviderStateMixin {
  static const _minScale = 1.0;
  static const _maxScale = 5.0;

  double _scale = 1;
  Offset _offset = Offset.zero;
  double _scaleStart = 1;
  Offset _offsetStart = Offset.zero;
  Offset _focalStart = Offset.zero;

  late final AnimationController _resetCtrl;
  Animation<double>? _scaleAnim;
  Animation<Offset>? _offsetAnim;

  @override
  void initState() {
    super.initState();
    _resetCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        final s = _scaleAnim;
        final o = _offsetAnim;
        if (s == null || o == null) return;
        setState(() {
          _scale = s.value;
          _offset = o.value;
        });
      });
  }

  @override
  void dispose() {
    _resetCtrl.dispose();
    super.dispose();
  }

  void _animateReset() {
    _resetCtrl.stop();
    _scaleAnim = Tween<double>(begin: _scale, end: 1).animate(
      CurvedAnimation(parent: _resetCtrl, curve: Curves.easeOutCubic),
    );
    _offsetAnim = Tween<Offset>(begin: _offset, end: Offset.zero).animate(
      CurvedAnimation(parent: _resetCtrl, curve: Curves.easeOutCubic),
    );
    _resetCtrl.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _scale = 1;
        _offset = Offset.zero;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = CachedNetworkImage(
      imageUrl: widget.url,
      fit: BoxFit.contain,
    );
    final tagged = widget.heroTag != null
        ? Hero(tag: widget.heroTag!, child: image)
        : image;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _animateReset,
        onScaleStart: (d) {
          _resetCtrl.stop();
          _scaleStart = _scale;
          _offsetStart = _offset;
          _focalStart = d.focalPoint;
        },
        onScaleUpdate: (d) {
          setState(() {
            _scale = (_scaleStart * d.scale).clamp(_minScale, _maxScale);
            if (_scale > 1.02) {
              _offset = _offsetStart + (d.focalPoint - _focalStart);
            } else {
              _offset = Offset.zero;
            }
          });
        },
        child: Center(
          child: Transform.translate(
            offset: _offset,
            child: Transform.scale(
              scale: _scale,
              child: tagged,
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoViewerSheet extends StatefulWidget {
  const _VideoViewerSheet({required this.url});

  final String url;

  @override
  State<_VideoViewerSheet> createState() => _VideoViewerSheetState();
}

class _VideoViewerSheetState extends State<_VideoViewerSheet> {
  VideoPlayerController? _controller;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      if (!mounted) return;
      setState(() {
        _controller = c;
        _ready = true;
      });
      await c.play();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)))
                  : !_ready
                      ? const Center(child: CircularProgressIndicator(color: Colors.white))
                      : AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        ),
            ),
            if (_ready)
              IconButton(
                onPressed: () {
                  setState(() {
                    _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
                  });
                },
                icon: Icon(
                  _controller!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  color: Colors.white,
                  size: 48,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
