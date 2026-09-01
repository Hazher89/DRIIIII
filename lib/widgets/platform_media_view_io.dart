import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

Widget buildPlatformMediaView(
  String url, {
  bool isAudio = false,
  bool autoplay = true,
  bool muted = true,
}) {
  return _InlineMediaPlayer(
    url: url,
    isAudio: isAudio,
    autoplay: autoplay,
    muted: muted,
  );
}

class _InlineMediaPlayer extends StatefulWidget {
  const _InlineMediaPlayer({
    required this.url,
    required this.isAudio,
    required this.autoplay,
    required this.muted,
  });

  final String url;
  final bool isAudio;
  final bool autoplay;
  final bool muted;

  @override
  State<_InlineMediaPlayer> createState() => _InlineMediaPlayerState();
}

class _InlineMediaPlayerState extends State<_InlineMediaPlayer> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = await _createController(widget.url);
      await c.initialize();
      await c.setVolume(widget.muted ? 0 : 1);
      if (!widget.isAudio) {
        await c.setLooping(true);
      }
      c.addListener(_onTick);
      if (!mounted) return;
      setState(() {
        _controller = c;
        _loading = false;
      });
      if (widget.autoplay) {
        await c.play();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<VideoPlayerController> _createController(String url) async {
    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma < 0) throw StateError('Ugyldig data-URL');
      final bytes = base64Decode(url.substring(comma + 1));
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/driftpro_feed_${url.hashCode}.mp4');
      await file.writeAsBytes(bytes, flush: true);
      return VideoPlayerController.file(file);
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return VideoPlayerController.networkUrl(Uri.parse(url));
    }
    final path =
        url.startsWith('file://') ? url.replaceFirst('file://', '') : url;
    return VideoPlayerController.file(File(path));
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null || _controller == null) {
      return const Center(child: Icon(Icons.videocam_off_outlined));
    }

    final c = _controller!;
    final playing = c.value.isPlaying;
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: VideoPlayer(c),
            ),
          ),
          if (!playing)
            Container(
              color: Colors.black26,
              child: const Icon(
                Icons.play_circle_fill,
                size: 56,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}
