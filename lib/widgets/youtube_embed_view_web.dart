// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

Widget buildYoutubeEmbed({
  required String videoId,
  required double height,
  bool autoplay = false,
  bool muted = true,
}) {
  return _WebYoutubeEmbed(
    videoId: videoId,
    height: height,
    autoplay: autoplay,
    muted: muted,
  );
}

class _WebYoutubeEmbed extends StatefulWidget {
  const _WebYoutubeEmbed({
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
  State<_WebYoutubeEmbed> createState() => _WebYoutubeEmbedState();
}

class _WebYoutubeEmbedState extends State<_WebYoutubeEmbed> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'yt-${widget.videoId}-${widget.hashCode}';
    final params = <String>[
      'rel=0',
      'modestbranding=1',
      if (widget.autoplay) 'autoplay=1',
      if (widget.muted) 'mute=1',
    ];
    final src =
        'https://www.youtube.com/embed/${widget.videoId}?${params.join('&')}';
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int _) {
      final iframe = html.IFrameElement()
        ..src = src
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = true
        ..allow = 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture';
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: HtmlElementView(viewType: _viewId),
    );
  }
}
