import 'package:flutter/material.dart';

import 'platform_media_view_stub.dart'
    if (dart.library.html) 'platform_media_view_web.dart'
    if (dart.library.io) 'platform_media_view_io.dart' as impl;

class PlatformMediaView extends StatelessWidget {
  final String url;
  final bool isAudio;

  const PlatformMediaView({
    super.key,
    required this.url,
    this.isAudio = false,
  });

  @override
  Widget build(BuildContext context) {
    return impl.buildPlatformMediaView(url, isAudio: isAudio);
  }
}
