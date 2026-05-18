import 'package:flutter/material.dart';

import 'platform_embedded_view_stub.dart'
    if (dart.library.html) 'platform_embedded_view_web.dart' as impl;

/// Innebygd visning av vilkårlig URL (PDF, bilder, m.m.) i nettleseren.
class PlatformEmbeddedView extends StatelessWidget {
  final String url;
  final String? mimeHint;

  const PlatformEmbeddedView({
    super.key,
    required this.url,
    this.mimeHint,
  });

  @override
  Widget build(BuildContext context) {
    return impl.buildPlatformEmbeddedView(url, mimeHint: mimeHint);
  }
}
