// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

Widget buildPlatformMediaView(String url, {bool isAudio = false}) {
  return _WebMediaElement(url: url, isAudio: isAudio);
}

class _WebMediaElement extends StatefulWidget {
  final String url;
  final bool isAudio;
  const _WebMediaElement({required this.url, required this.isAudio});

  @override
  State<_WebMediaElement> createState() => _WebMediaElementState();
}

class _WebMediaElementState extends State<_WebMediaElement> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'media-${widget.url.hashCode}';
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int _) {
      final el = widget.isAudio
          ? html.AudioElement()
          : html.VideoElement();
      el.src = widget.url;
      el.controls = true;
      el.style.width = '100%';
      el.style.height = '100%';
      if (!widget.isAudio) {
        (el as html.VideoElement)
          ..style.maxHeight = '100%'
          ..style.objectFit = 'contain';
      }
      return el;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: double.infinity,
        height: widget.isAudio ? 80 : double.infinity,
        child: HtmlElementView(viewType: _viewId),
      ),
    );
  }
}
