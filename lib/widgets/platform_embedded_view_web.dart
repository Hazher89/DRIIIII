// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

Widget buildPlatformEmbeddedView(String url, {String? mimeHint}) {
  return _WebEmbeddedFrame(url: url, mimeHint: mimeHint);
}

class _WebEmbeddedFrame extends StatefulWidget {
  final String url;
  final String? mimeHint;
  const _WebEmbeddedFrame({required this.url, this.mimeHint});

  @override
  State<_WebEmbeddedFrame> createState() => _WebEmbeddedFrameState();
}

class _WebEmbeddedFrameState extends State<_WebEmbeddedFrame> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'embed-${widget.url.hashCode}';
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int _) {
      final iframe = html.IFrameElement()
        ..src = widget.url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = true;
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewId);
  }
}
