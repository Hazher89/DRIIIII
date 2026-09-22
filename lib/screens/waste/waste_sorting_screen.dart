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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Komprimatorer', style: DriftProTheme.headingSm),
            const SizedBox(height: 6),
            Text(
              'A = papp (brettet). B = annet (isopor OK). '
              'Avvik = video 2+2 min. Trykk klipp for studio · BOT direkte fra video.',
              style: TextStyle(
                color: Colors.grey.shade700,
                height: 1.35,
                fontSize: 13,
              ),
            ),
            if (cameras.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...cameras.map(
                (c) => Text(
                  '● ${c.name} · ${c.host}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ),
            ],
            if (canAdmin) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => context.push(AppPaths.moreVisionCameras),
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Kamera-innstillinger'),
              ),
            ],
          ],
        ),
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
                size: 48, color: Colors.grey.shade400),
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

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
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
  }
}

class _SortingClipCard extends StatelessWidget {
  const _SortingClipCard({required this.event, required this.onTap});

  final VisionEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time =
        DateFormat('dd.MM.yyyy HH:mm').format(event.occurredAt.toLocal());
    final thumb = event.dropboxImageUrl;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        elevation: 1,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
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
                              color: Colors.white54),
                        ),
                      )
                    else
                      Container(
                        color: Colors.grey.shade900,
                        child: const Icon(Icons.play_circle_outline,
                            color: Colors.white54, size: 48),
                      ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.75),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    const Center(
                      child: Icon(
                        Icons.play_circle_filled,
                        color: Colors.white,
                        size: 56,
                      ),
                    ),
                    Positioned(
                      left: 10,
                      bottom: 10,
                      right: 10,
                      child: Text(
                        event.violationSummary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (!event.isViewed)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: DriftProTheme.primaryGreen,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'NY',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    if (event.videoUrl != null)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'VIDEO',
                            style: TextStyle(
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
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      time,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final chip in event.insightChips.take(4))
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: DriftProTheme.primaryGreen
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              chip,
                              style: TextStyle(
                                fontSize: 11,
                                color: DriftProTheme.primaryGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
