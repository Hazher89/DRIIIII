import 'package:flutter/material.dart';

import '../../../core/services/vision/vision_camera_service.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Ikke-web: vis lenke til lokal dashboard.
Widget buildLocalWorkerLiveFeed() {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DriftProLoadingIndicator(),
          const SizedBox(height: 12),
          Text(
            'Live feed er optimalisert for web.\n'
            'Åpne ${VisionCameraService.localWorkerLiveUrl.replaceAll('/live.jpg', '')} i nettleser.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}
