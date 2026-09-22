import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/layout/mobile_shell_scaffold.dart';
import '../../core/permissions/user_access.dart';
import '../../core/routing/app_paths.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/vision/vision_camera_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';
import '../../models/vision_camera.dart';
import '../../widgets/driftpro_loading_indicator.dart';
import 'waste_sorting_studio.dart';

/// Søppelhåndtering — feed + avansert videostudio.
class WasteSortingScreen extends StatefulWidget {
  const WasteSortingScreen({super.key});

  @override
  State<WasteSortingScreen> createState() => _WasteSortingScreenState();
}

class _WasteSortingScreenState extends State<WasteSortingScreen>
    with SingleTickerProviderStateMixin {
  List<VisionEvent> _events = [];
  List<VisionCamera> _cameras = [];
  UserProfile? _profile;
  bool _loading = true;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      final events = await VisionCameraService.instance.fetchSortingEvents(
        limit: 120,
        includeArchived: true,
      );
      final cameras = await VisionCameraService.instance.fetchCameras();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _events = events.where((e) => !e.isDismissed).toList();
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

  List<VisionEvent> get _newEvents =>
      _events.where((e) => !e.isArchived && !e.isViewed).toList();

  List<VisionEvent> get _seenEvents =>
      _events.where((e) => !e.isArchived && e.isViewed).toList();

  List<VisionEvent> get _archivedEvents =>
      _events.where((e) => e.isArchived).toList();

  Future<void> _openStudio(VisionEvent event, List<VisionEvent> playlist) async {
    final updated = await openWasteSortingStudio(
      context,
      event: event,
      playlist: playlist,
    );
    if (updated != null) {
      await _load();
    } else {
      // Marked as viewed inside studio — refresh badges.
      await _load();
    }
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
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _IntroCard(cameras: _cameras, canAdmin: _canAdmin),
              ),
              TabBar(
                controller: _tabs,
                labelColor: DriftProTheme.primaryGreen,
                tabs: [
                  Tab(text: 'Nye (${_newEvents.length})'),
                  Tab(text: 'Sett (${_seenEvents.length})'),
                  Tab(text: 'Arkiv (${_archivedEvents.length})'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _EventFeed(
                      events: _newEvents,
                      emptyLabel: 'Ingen nye klipp.',
                      onOpen: (e) => _openStudio(e, _newEvents),
                      onRefresh: _load,
                    ),
                    _EventFeed(
                      events: _seenEvents,
                      emptyLabel: 'Ingen sette klipp ennå.',
                      onOpen: (e) => _openStudio(e, _seenEvents),
                      onRefresh: _load,
                    ),
                    _EventFeed(
                      events: _archivedEvents,
                      emptyLabel: 'Arkivet er tomt.',
                      onOpen: (e) => _openStudio(e, _archivedEvents),
                      onRefresh: _load,
                    ),
                  ],
                ),
              ),
            ],
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Avvik-klipp · A=papp · B=annet',
                  style: DriftProTheme.headingSm.copyWith(fontSize: 15),
                ),
                if (cameras.isNotEmpty)
                  Text(
                    cameras.map((c) => c.name).join(' · '),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (canAdmin)
            TextButton(
              onPressed: () => context.push(AppPaths.moreVisionCameras),
              child: const Text('Kamera'),
            ),
        ],
      ),
    );
  }
}

class _EventFeed extends StatelessWidget {
  const _EventFeed({
    required this.events,
    required this.emptyLabel,
    required this.onOpen,
    required this.onRefresh,
  });

  final List<VisionEvent> events;
  final String emptyLabel;
  final ValueChanged<VisionEvent> onOpen;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          padding: const EdgeInsets.all(32),
          children: [
            Icon(Icons.videocam_off_outlined,
                size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              emptyLabel,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 1100
            ? 4
            : w >= 760
                ? 3
                : 2;
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 24),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 10,
              mainAxisSpacing: 14,
              // YouTube-ish: 16:9 thumb + compact meta under
              childAspectRatio: cols >= 3 ? 0.92 : 0.78,
            ),
            itemCount: events.length,
            itemBuilder: (context, i) {
              final e = events[i];
              return _SortingClipCard(
                event: e,
                onTap: () => onOpen(e),
              );
            },
          ),
        );
      },
    );
  }
}

class _SortingClipCard extends StatelessWidget {
  const _SortingClipCard({required this.event, required this.onTap});

  final VisionEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time =
        DateFormat('dd.MM HH:mm').format(event.occurredAt.toLocal());
    final thumb = event.dropboxImageUrl;
    final hasVideo = event.videoUrl != null ||
        (event.videoDropboxPath?.toLowerCase().endsWith('.mp4') ?? false);
    final before = event.metadata['clip_seconds_before'];
    final after = event.metadata['clip_seconds_after'];
    String? durationLabel;
    if (before is num && after is num) {
      final total = (before + after).round();
      final m = total ~/ 60;
      final s = total % 60;
      durationLabel = '$m:${s.toString().padLeft(2, '0')}';
    } else if (hasVideo) {
      durationLabel = 'VIDEO';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (thumb.isNotEmpty)
                      Image.network(
                        thumb,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade900,
                          child: const Icon(Icons.broken_image_outlined,
                              color: Colors.white54, size: 28),
                        ),
                      )
                    else
                      Container(
                        color: Colors.grey.shade900,
                        child: const Icon(Icons.play_circle_outline,
                            color: Colors.white54, size: 36),
                      ),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          hasVideo
                              ? Icons.play_arrow_rounded
                              : Icons.image_outlined,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    if (!event.isViewed)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: DriftProTheme.primaryGreen,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'NY',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),
                    if (durationLabel != null)
                      Positioned(
                        bottom: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            durationLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.violationSummary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      time,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                      ),
                    ),
                    if (event.insightChips.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        event.insightChips.take(2).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
