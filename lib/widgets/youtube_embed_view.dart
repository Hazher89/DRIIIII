import 'package:flutter/material.dart';

import 'youtube_embed_view_stub.dart'
    if (dart.library.html) 'youtube_embed_view_web.dart' as impl;

class YoutubeEmbedView extends StatelessWidget {
  const YoutubeEmbedView({
    super.key,
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
  Widget build(BuildContext context) {
    return impl.buildYoutubeEmbed(
      videoId: videoId,
      height: height,
      autoplay: autoplay,
      muted: muted,
    );
  }
}
