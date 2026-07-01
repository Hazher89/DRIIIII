// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import '../../../core/services/vision/vision_camera_service.dart';

/// Live feed via iframe mot lokal worker-dashboard (fungerer i Chrome).
Widget buildLocalWorkerLiveFeed() {
  return const _WebWorkerLiveFrame();
}

class _WebWorkerLiveFrame extends StatefulWidget {
  const _WebWorkerLiveFrame();

  @override
  State<_WebWorkerLiveFrame> createState() => _WebWorkerLiveFrameState();
}

class _WebWorkerLiveFrameState extends State<_WebWorkerLiveFrame> {
  static int _seq = 0;
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'vision-live-iframe-${_seq++}';
    final dashboard = VisionCameraService.localWorkerLiveUrl
        .replaceAll('/live.jpg', '/');
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int _) {
      return html.IFrameElement()
        ..src = dashboard
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'camera';
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = VisionCameraService.localWorkerLiveUrl
        .replaceAll('/live.jpg', '/');
    return Column(
      children: [
        Expanded(child: HtmlElementView(viewType: _viewId)),
        TextButton.icon(
          onPressed: () => html.window.open(dashboard, '_blank'),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Åpne kamera-dashboard i ny fane'),
        ),
      ],
    );
  }
}
