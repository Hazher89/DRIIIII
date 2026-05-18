import 'package:flutter/material.dart';

import 'platform_office_view_stub.dart'
    if (dart.library.html) 'platform_office_view_web.dart' as impl;

/// Forhåndsvisning av Office-filer via innebygd viser (web).
class PlatformOfficeView extends StatelessWidget {
  final String url;

  const PlatformOfficeView({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return impl.buildPlatformOfficeView(url);
  }
}
