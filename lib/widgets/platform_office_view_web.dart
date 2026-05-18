// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

Widget buildPlatformOfficeView(String url) {
  return _WebOfficeIframe(url: url);
}

class _WebOfficeIframe extends StatefulWidget {
  final String url;
  const _WebOfficeIframe({required this.url});

  @override
  State<_WebOfficeIframe> createState() => _WebOfficeIframeState();
}

class _WebOfficeIframeState extends State<_WebOfficeIframe> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    final encoded = Uri.encodeComponent(widget.url);
    final viewer =
        'https://docs.google.com/gview?url=$encoded&embedded=true';
    _viewId = 'office-${widget.url.hashCode}';
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int _) {
      final iframe = html.IFrameElement()
        ..src = viewer
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
