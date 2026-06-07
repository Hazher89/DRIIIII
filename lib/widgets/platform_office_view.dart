import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'platform_office_view_stub.dart'
    if (dart.library.html) 'platform_office_view_web.dart' as impl;

/// Forhåndsvisning av Office-filer med original layout.
class PlatformOfficeView extends StatelessWidget {
  final String url;
  final Uint8List? bytes;
  final String? extension;

  const PlatformOfficeView({
    super.key,
    required this.url,
    this.bytes,
    this.extension,
  });

  @override
  Widget build(BuildContext context) {
    return impl.buildPlatformOfficeView(
      url,
      bytes: bytes,
      extension: extension,
    );
  }
}
