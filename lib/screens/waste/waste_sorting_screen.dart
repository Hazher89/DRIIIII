import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/layout/mobile_shell_scaffold.dart';
import '../../core/permissions/user_access.dart';
import '../../core/routing/app_paths.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/vision/vision_camera_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';
import '../../models/vision_camera.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Søppelhåndtering / komprimator-klipp fra vision worker.
class WasteSortingScreen extends StatefulWidget {
  const WasteSortingScreen({super.key});

  @override
  State<WasteSortingScreen> createState() => _WasteSortingScreenState();
}

class _WasteSortingScreenState extends State<WasteSortingScreen> {
  List<VisionEvent> _events = [];
  List<VisionCamera> _cameras = [];
  UserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      final events =
          await VisionCameraService.instance.fetchSortingEvents(limit: 80);
      final cameras = await VisionCameraService.instance.fetchCameras();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _events = events;
        _cameras = cameras
            .where((c) => c.eventType == 'sorting_clip' && c.enabled)
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke laste søppelhåndtering: $e')),
      );
    }
  }

  bool get _canAdmin {
    final access = UserAccess.of(_profile);
    return access?.canUniformMonitorAdmin == true ||
        _profile?.isSuperAdmin == true;
  }

  @override
  Widget build(BuildContext context) {
    final access = UserAccess.of(_profile);
    if (access != null &&
        !access.canUniformMonitor &&
        !access.canUniformMonitorAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Søppelhåndtering')),
        body: const Center(child: Text('Du har ikke tilgang.')),
      );
    }

    final body = _loading
        ? const DriftProLoadingCenter()
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _IntroCard(cameras: _cameras, canAdmin: _canAdmin),
                const SizedBox(height: 16),
                Text('Klipp og hendelser', style: DriftProTheme.headingSm),
                const SizedBox(height: 8),
                if (_events.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      children: [
                        Icon(Icons.delete_outline,
                            size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          'Ingen klipp ennå.\nNår jobb-PC-en kjører workeren, dukker de opp her.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                else
                  ..._events.map((e) => _SortingEventCard(event: e)),
              ],
            ),
          );

    return MobileShellScaffold(
      title: 'Søppelhåndtering',
      actions: [
        if (_canAdmin)
          IconButton(
            tooltip: 'Kameraer',
            onPressed: () => context.push(AppPaths.moreVisionCameras),
            icon: const Icon(Icons.videocam_outlined),
          ),
        IconButton(
          tooltip: 'Oppdater',
          onPressed: _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: body,
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.cameras, required this.canAdmin});

  final List<VisionCamera> cameras;
  final bool canAdmin;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Komprimatorer', style: DriftProTheme.headingSm),
            const SizedBox(height: 8),
            Text(
              'Kamera ser begge komprimatorene. Ved brun eske eller stor/full '
              'emballasje lagres ~1 min før og etter.',
              style: TextStyle(color: Colors.grey.shade700, height: 1.35),
            ),
            const SizedBox(height: 12),
            if (cameras.isEmpty)
              Text(
                canAdmin
                    ? 'Ingen sorteringskamera registrert. Gå til Mer → Kameraer og legg til med type «Søppelsortering».'
                    : 'Ingen sorteringskamera er satt opp ennå.',
                style: TextStyle(color: Colors.orange.shade800),
              )
            else
              ...cameras.map(
                (c) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    c.enabled ? Icons.videocam : Icons.videocam_off,
                    color: c.enabled ? Colors.green : Colors.grey,
                  ),
                  title: Text(c.name),
                  subtitle: Text('${c.host} · ${c.eventTypeLabel}'),
                ),
              ),
            if (canAdmin) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => context.push(AppPaths.moreVisionCameras),
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Kamera-innstillinger'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SortingEventCard extends StatelessWidget {
  const _SortingEventCard({required this.event});

  final VisionEvent event;

  @override
  Widget build(BuildContext context) {
    final time =
        DateFormat('dd.MM.yyyy HH:mm:ss').format(event.occurredAt.toLocal());
    final url = event.dropboxImageUrl;
    final zone = event.metadata['zone']?.toString();
    final reason = event.metadata['reason']?.toString();
    final videoPath = event.metadata['video_path']?.toString();

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
            title: Text(event.violationSummary),
            subtitle: Text(
              [
                time,
                if (zone != null && zone.isNotEmpty) zone,
                if (reason != null && reason.isNotEmpty) reason,
              ].join(' · '),
            ),
            trailing: videoPath != null && videoPath.startsWith('http')
                ? IconButton(
                    tooltip: 'Åpne video',
                    icon: const Icon(Icons.play_circle_outline),
                    onPressed: () => launchUrl(
                      Uri.parse(videoPath),
                      mode: LaunchMode.externalApplication,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
