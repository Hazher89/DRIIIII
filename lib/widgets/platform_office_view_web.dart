// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

Widget buildPlatformOfficeView(
  String url, {
  Uint8List? bytes,
  String? extension,
}) {
  final ext = extension?.toLowerCase();
  if (ext == 'docx' && bytes != null) {
    return _DocxJsPreview(bytes: bytes, fallbackUrl: url);
  }
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
        'https://view.officeapps.live.com/op/embed.aspx?src=$encoded';
    _viewId = 'office-${widget.url.hashCode}';
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int _) {
      final iframe = html.IFrameElement()
        ..src = viewer
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

class _DocxJsPreview extends StatefulWidget {
  final Uint8List bytes;
  final String fallbackUrl;

  const _DocxJsPreview({
    required this.bytes,
    required this.fallbackUrl,
  });

  @override
  State<_DocxJsPreview> createState() => _DocxJsPreviewState();
}

class _DocxJsPreviewState extends State<_DocxJsPreview> {
  late final String _viewId;
  var _failed = false;
  var _useOfficeOnline = false;

  @override
  void initState() {
    super.initState();
    _viewId = 'docx-js-${widget.bytes.hashCode}';
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int _) {
      final container = html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.overflow = 'auto'
        ..style.backgroundColor = '#ffffff'
        ..style.padding = '16px';
      _renderDocx(container);
      return container;
    });
  }

  Future<void> _renderDocx(html.DivElement container) async {
    try {
      final docx = js.context['docx'];
      if (docx == null) {
        throw StateError('docx-preview er ikke lastet');
      }
      final blob = html.Blob([widget.bytes]);
      final options = js.JsObject.jsify({
        'className': 'docx-preview-content',
        'inWrapper': true,
        'ignoreWidth': false,
        'ignoreHeight': false,
        'breakPages': true,
      });
      await docx.callMethod('renderAsync', [blob, container, null, options]);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_useOfficeOnline) {
      return _WebOfficeIframe(url: widget.fallbackUrl);
    }
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Kunne ikke vise dokumentet i nettleseren.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => setState(() => _useOfficeOnline = true),
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Prøv Word Online'),
            ),
          ],
        ),
      );
    }
    return HtmlElementView(viewType: _viewId);
  }
}
