import 'package:flutter/material.dart';

Widget buildYoutubeEmbed({
  required String videoId,
  required double height,
  bool autoplay = false,
  bool muted = true,
}) {
  return Container(
    height: height,
    color: Colors.black87,
    alignment: Alignment.center,
    child: Icon(Icons.play_circle_outline, color: Colors.white.withValues(alpha: 0.7), size: 48),
  );
}
