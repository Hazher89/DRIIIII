import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

Widget buildYoutubeEmbed({
  required String videoId,
  required double height,
  bool autoplay = false,
  bool muted = true,
}) {
  return _NativeYoutubeEmbed(
    videoId: videoId,
    height: height,
    autoplay: autoplay,
    muted: muted,
  );
}

class _NativeYoutubeEmbed extends StatefulWidget {
  const _NativeYoutubeEmbed({
    required this.videoId,
    required this.height,
    this.autoplay = false,
    this.muted = true,
  });

  final String videoId;
  final double height;
  final bool autoplay;
  final bool muted;

  @override
  State<_NativeYoutubeEmbed> createState() => _NativeYoutubeEmbedState();
}

class _NativeYoutubeEmbedState extends State<_NativeYoutubeEmbed> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final params = <String>[
      'rel=0',
      'modestbranding=1',
      'playsinline=1',
      if (widget.autoplay) 'autoplay=1',
      if (widget.muted) 'mute=1',
    ];
    final src =
        'https://www.youtube.com/embed/${widget.videoId}?${params.join('&')}';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(src));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const ColoredBox(
              color: Colors.black87,
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
              ),
            ),
        ],
      ),
    );
  }
}
