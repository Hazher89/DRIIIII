import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/vision/vision_camera_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/vision_camera.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Viser vision-hendelser med bilde fra Dropbox / lokal worker.
class VisionEventsScreen extends StatefulWidget {
  const VisionEventsScreen({super.key});

  @override
  State<VisionEventsScreen> createState() => _VisionEventsScreenState();
}

class _VisionEventsScreenState extends State<VisionEventsScreen> {
  List<VisionEvent> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final events = await VisionCameraService.instance.fetchRecentEvents();
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke laste hendelser: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kamerahendelser')),
      body: _loading
          ? const DriftProLoadingCenter()
          : _events.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_busy, size: 56, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text('Ingen hendelser ennå', style: DriftProTheme.headingSm),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _events.length,
                    itemBuilder: (context, i) => _EventCard(event: _events[i]),
                  ),
                ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final VisionEvent event;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('dd.MM HH:mm:ss').format(event.occurredAt.toLocal());
    final url = event.dropboxImageUrl;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (url.isNotEmpty)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade200,
                  child: const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          ListTile(
            title: Text(event.eventType, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Kamera: ${event.cameraId} · $time'),
            trailing: Chip(
              label: Text(event.status),
              backgroundColor: DriftProTheme.success.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}
