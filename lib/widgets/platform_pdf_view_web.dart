// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

Widget buildPlatformPdfView(String url) {
  return _WebPdfIframe(url: url);
}

class _WebPdfIframe extends StatefulWidget {
  final String url;
  const _WebPdfIframe({required this.url});

  @override
  State<_WebPdfIframe> createState() => _WebPdfIframeState();
}

class _WebPdfIframeState extends State<_WebPdfIframe> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'pdf-${widget.url.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int _) {
      final iframe = html.IFrameElement()
        ..src = widget.url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewId);
  }
}
