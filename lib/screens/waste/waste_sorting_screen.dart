import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../core/layout/mobile_shell_scaffold.dart';
import '../../core/permissions/user_access.dart';
import '../../core/routing/app_paths.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/vision/vision_camera_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';
import '../../models/vision_camera.dart';
import '../../widgets/driftpro_loading_indicator.dart';
import 'waste_learn_panel.dart';
import 'waste_sorting_studio.dart';

/// Søppelhåndtering — YouTube-stil: kun videoklipp, spillervindu + sidepanel.
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

  VisionEvent? _selected;
  VideoPlayerController? _player;
  bool _playerReady = false;
  String? _playerError;
  bool _busy = false;
  DateTime? _playerTickAt;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      // Bytt fane → lukk spiller hvis valgt klipp ikke finnes i fanen.
      final list = _tabPlaylist;
      if (_selected != null && !list.any((e) => e.id == _selected!.id)) {
        _clearSelection(keepTab: true);
      }
      setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    final p = _player;
    if (p != null) {
      p.removeListener(_onPlayerTick);
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      final events = await VisionCameraService.instance.fetchSortingEvents(
        limit: 120,
        includeArchived: true,
      );
      final cameras = await VisionCameraService.instance.fetchCameras();
      if (!mounted) return;
      final videoOnly = events
          .where((e) => !e.isDismissed && e.hasVideoClip)
          .toList();
      setState(() {
        _profile = profile;
        _events = videoOnly;
        _cameras = cameras
            .where((c) => c.eventType == 'sorting_clip' && c.enabled)
            .toList();
        _loading = false;
        // Oppdater valgt klipp fra fersk data — ikke restart spiller.
        if (_selected != null) {
          final fresh = videoOnly.where((e) => e.id == _selected!.id);
          if (fresh.isEmpty) {
            _selected = null;
            unawaited(_disposePlayer());
          } else {
            _selected = fresh.first;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke laste søppelhåndtering: $e')),
        );
      }
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

  List<VisionEvent> get _tabPlaylist {
    switch (_tabs.index) {
      case 1:
        return _seenEvents;
      case 2:
        return _archivedEvents;
      default:
        return _newEvents;
    }
  }

  Future<void> _disposePlayer() async {
    final old = _player;
    _player = null;
    _playerReady = false;
    _playerError = null;
    if (old != null) {
      old.removeListener(_onPlayerTick);
      await old.dispose();
    }
  }

  void _clearSelection({bool keepTab = false}) {
    final current = _selected;
    if (current != null && !current.isViewed) {
      unawaited(_markViewedQuiet(current));
    }
    unawaited(_disposePlayer());
    setState(() => _selected = null);
  }

  Future<void> _selectVideo(VisionEvent event) async {
    final previous = _selected;
    // Merk forrige som sett først når man bytter video — ikke ved åpning.
    if (previous != null && previous.id != event.id) {
      await _markViewedQuiet(previous);
    }

    setState(() {
      _selected = event;
      _playerReady = false;
      _playerError = null;
    });
    await _disposePlayer();
    await _loadPlayer(event);
  }

  Future<void> _markViewedQuiet(VisionEvent event) async {
    if (event.isViewed) return;
    try {
      final updated =
          await VisionCameraService.instance.markSortingEventViewed(event.id);
      if (!mounted) return;
      setState(() {
        final i = _events.indexWhere((e) => e.id == updated.id);
        if (i >= 0) _events[i] = updated;
      });
    } catch (_) {}
  }

  Future<void> _loadPlayer(VisionEvent event) async {
    final fresh =
        await VisionCameraService.instance.resolveEventMediaLink(event.id);
    String? url;
    String? resolveHint;
    // Dropbox temporary links har ofte ikke .mp4 i URL — stol på media_link.
    if (fresh != null && !fresh.isImage && fresh.url.startsWith('http')) {
      url = fresh.url;
    } else if (event.videoDropboxPath != null) {
      final byPath = await VisionCameraService.instance
          .resolveDropboxPathLink(event.videoDropboxPath!);
      if (byPath != null &&
          !byPath.isImage &&
          byPath.url.startsWith('http')) {
        url = byPath.url;
      } else {
        resolveHint = 'media_link feilet for sti';
      }
    } else if (fresh == null) {
      resolveHint = 'Kunne ikke hente fersk Dropbox-lenke';
    }
    // Bruk lagret URL kun hvis den ser ut som spillbar CDN (midlertidige lenker utløper).
    if (url == null &&
        event.videoUrl != null &&
        event.videoUrl!.startsWith('http') &&
        _looksLikeMediaCdn(event.videoUrl!)) {
      url = event.videoUrl;
    }

    if (url == null || url.isEmpty || !url.startsWith('http')) {
      if (mounted) {
        setState(() {
          _playerError =
              'Ingen videofil på dette klippet.\n'
              '${resolveHint ?? "Kun MP4 som er lastet til Dropbox vises her."}\n\n'
              'Tips: vent til jobb-PC er ferdig med 2 min opptak etter feilkasting, '
              'eller kjør git pull + START_WINDOWS på nytt.';
          _playerReady = false;
        });
      }
      return;
    }

    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
      await c.setLooping(false);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _player = c;
        _playerReady = true;
        _playerError = null;
      });
      // Throttle — uten dette blinker hele siden flere ganger i sekundet.
      c.addListener(_onPlayerTick);
    } catch (e) {
      if (mounted) {
        setState(() {
          _playerError =
              'Kunne ikke spille video: $e\n\nTips: gamle klipp kan ha feil codec. '
              'Oppdater Windows-worker (git pull) og lag et nytt avvik.';
          _playerReady = false;
        });
      }
    }
  }

  void _onPlayerTick() {
    final now = DateTime.now();
    if (_playerTickAt != null &&
        now.difference(_playerTickAt!) < const Duration(milliseconds: 300)) {
      return;
    }
    _playerTickAt = now;
    if (mounted) setState(() {});
  }

  bool _looksLikeVideo(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.mp4') ||
        lower.contains('.mov') ||
        lower.contains('.webm') ||
        lower.contains('content_type=video');
  }

  bool _looksLikeMediaCdn(String url) {
    final lower = url.toLowerCase();
    return lower.contains('dropboxusercontent.com') ||
        lower.contains('dropbox.com') ||
        lower.contains('dl.dropbox');
  }

  Future<void> _togglePlay() async {
    final c = _player;
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
    setState(() {});
  }

  void _seekBy(Duration delta) {
    final c = _player;
    if (c == null || !c.value.isInitialized) return;
    final next = c.value.position + delta;
    final dur = c.value.duration;
    final clamped = next < Duration.zero
        ? Duration.zero
        : (next > dur ? dur : next);
    c.seekTo(clamped);
  }

  Future<void> _openBot() async {
    final ev = _selected;
    if (ev == null) return;
    await _player?.pause();
    if (!mounted) return;
    final result = await showWasteBotSheet(context, event: ev);
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('BOT sendt til partner')),
      );
    }
  }

  Future<void> _archiveSelected({required bool archived}) async {
    final ev = _selected;
    if (ev == null) return;
    setState(() => _busy = true);
    try {
      final updated = await VisionCameraService.instance.setSortingEventArchived(
        ev.id,
        archived: archived,
      );
      if (!mounted) return;
      setState(() {
        final i = _events.indexWhere((e) => e.id == updated.id);
        if (i >= 0) _events[i] = updated;
        _selected = updated;
        _busy = false;
        if (archived) _tabs.animateTo(2);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: DriftProTheme.error),
        );
      }
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
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Column(
                  children: [
                    _IntroBar(cameras: _cameras, canAdmin: _canAdmin),
                    const SizedBox(height: 8),
                    WasteLearnPanel(
                      cameras: _cameras,
                      canAdmin: _canAdmin,
                      onChanged: () => _load(silent: true),
                    ),
                  ],
                ),
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
                  // Unngå horisontal swipe som «stjeler» vertikal scroll.
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildTabBody(_newEvents, 'Ingen nye videoklipp.'),
                    _buildTabBody(_seenEvents, 'Ingen sette videoklipp ennå.'),
                    _buildTabBody(_archivedEvents, 'Arkivet er tomt.'),
                  ],
                ),
              ),
            ],
          );

    return MobileShellScaffold(
      title: 'Søppelhåndtering',
      actions: [
        if (_selected != null)
          IconButton(
            tooltip: 'Tilbake til oversikt',
            onPressed: _clearSelection,
            icon: const Icon(Icons.grid_view_rounded),
          ),
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

  Widget _buildTabBody(List<VisionEvent> events, String emptyLabel) {
    if (events.isEmpty && _selected == null) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(48),
          children: [
            Icon(Icons.videocam_off_outlined,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              emptyLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Kun MP4-videoklipp vises her — ikke stillbilder. '
              'Pass på at Windows-worker laster opp video ved avvik.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.4),
            ),
          ],
        ),
      );
    }

    final selectedInTab =
        _selected != null && events.any((e) => e.id == _selected!.id);

    if (_selected != null && selectedInTab) {
      return _WatchLayout(
        selected: _selected!,
        playlist: events,
        player: _player,
        playerReady: _playerReady,
        playerError: _playerError,
        busy: _busy,
        onSelect: _selectVideo,
        onRefresh: _load,
        onTogglePlay: _togglePlay,
        onSeek: _seekBy,
        onBot: _openBot,
        onArchive: () =>
            _archiveSelected(archived: !_selected!.isArchived),
        onClose: _clearSelection,
      );
    }

    return _BrowseGrid(
      events: events,
      onOpen: _selectVideo,
      onRefresh: _load,
    );
  }
}

class _IntroBar extends StatelessWidget {
  const _IntroBar({required this.cameras, required this.canAdmin});

  final List<VisionCamera> cameras;
  final bool canAdmin;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Kun videoklipp · A=papp · B=annet',
            style: DriftProTheme.headingSm.copyWith(fontSize: 15),
          ),
        ),
        if (cameras.isNotEmpty)
          Flexible(
            child: Text(
              cameras.map((c) => c.name).join(' · '),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
        if (canAdmin)
          TextButton(
            onPressed: () => context.push(AppPaths.moreVisionCameras),
            child: const Text('Kamera'),
          ),
      ],
    );
  }
}

/// Oversikt: YouTube-hjem — store kort med stor gap.
class _BrowseGrid extends StatelessWidget {
  const _BrowseGrid({
    required this.events,
    required this.onOpen,
    required this.onRefresh,
  });

  final List<VisionEvent> events;
  final ValueChanged<VisionEvent> onOpen;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        // Færre kolonner + stor gap = YouTube-følelse, ikke tett mosaikk.
        final cols = w >= 1400
            ? 3
            : w >= 900
                ? 2
                : 1;
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: GridView.builder(
            padding: EdgeInsets.fromLTRB(
              w >= 900 ? 32 : 20,
              24,
              w >= 900 ? 32 : 20,
              40,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 28,
              mainAxisSpacing: 36,
              childAspectRatio: cols == 1 ? 1.35 : 1.15,
            ),
            itemCount: events.length,
            itemBuilder: (context, i) {
              return _VideoCard(
                event: events[i],
                onTap: () => onOpen(events[i]),
              );
            },
          ),
        );
      },
    );
  }
}

/// YouTube watch: stort spillervindu + restene i sidepanel.
class _WatchLayout extends StatelessWidget {
  const _WatchLayout({
    required this.selected,
    required this.playlist,
    required this.player,
    required this.playerReady,
    required this.playerError,
    required this.busy,
    required this.onSelect,
    required this.onRefresh,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onBot,
    required this.onArchive,
    required this.onClose,
  });

  final VisionEvent selected;
  final List<VisionEvent> playlist;
  final VideoPlayerController? player;
  final bool playerReady;
  final String? playerError;
  final bool busy;
  final ValueChanged<VisionEvent> onSelect;
  final Future<void> Function() onRefresh;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onBot;
  final VoidCallback onArchive;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final others = playlist.where((e) => e.id != selected.id).toList();
    final wide = MediaQuery.sizeOf(context).width >= 960;

    final playerPane = _MainPlayerPane(
      event: selected,
      player: player,
      ready: playerReady,
      error: playerError,
      busy: busy,
      onTogglePlay: onTogglePlay,
      onSeek: onSeek,
      onBot: onBot,
      onArchive: onArchive,
      onClose: onClose,
    );

    final side = _SidebarList(
      events: others,
      onSelect: onSelect,
      onRefresh: onRefresh,
    );

    if (wide) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 7,
                  child: SingleChildScrollView(
                    primary: false,
                    child: playerPane,
                  ),
                ),
                const SizedBox(width: 36),
                SizedBox(
                  width: 360,
                  height: constraints.maxHeight > 80
                      ? constraints.maxHeight
                      : null,
                  child: side,
                ),
              ],
            ),
          );
        },
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        primary: true,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          playerPane,
          const SizedBox(height: 28),
          Text(
            'Neste klipp',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 14),
          ...others.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: _SidebarTile(event: e, onTap: () => onSelect(e)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MainPlayerPane extends StatelessWidget {
  const _MainPlayerPane({
    required this.event,
    required this.player,
    required this.ready,
    required this.error,
    required this.busy,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onBot,
    required this.onArchive,
    required this.onClose,
  });

  final VisionEvent event;
  final VideoPlayerController? player;
  final bool ready;
  final String? error;
  final bool busy;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onBot;
  final VoidCallback onArchive;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = player;
    final progress = (c != null &&
            c.value.isInitialized &&
            c.value.duration.inMilliseconds > 0)
        ? c.value.position.inMilliseconds / c.value.duration.inMilliseconds
        : 0.0;
    final time =
        DateFormat('dd.MM.yyyy HH:mm').format(event.occurredAt.toLocal());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (error != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    )
                  else if (!ready || c == null)
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  else
                    FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: c.value.size.width,
                        height: c.value.size.height,
                        child: VideoPlayer(c),
                      ),
                    ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: IconButton(
                      onPressed: onClose,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                      ),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (ready && c != null) ...[
          Row(
            children: [
              IconButton(
                onPressed: () => onSeek(const Duration(seconds: -10)),
                icon: const Icon(Icons.replay_10),
              ),
              IconButton(
                onPressed: onTogglePlay,
                iconSize: 40,
                icon: Icon(
                  c.value.isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: DriftProTheme.primaryGreen,
                ),
              ),
              IconButton(
                onPressed: () => onSeek(const Duration(seconds: 10)),
                icon: const Icon(Icons.forward_10),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: Colors.grey.shade300,
                        color: DriftProTheme.primaryGreen,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_fmt(c.value.position),
                            style: const TextStyle(fontSize: 11)),
                        Text(_fmt(c.value.duration),
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Text(
          event.violationSummary,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          time,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        if (event.insightChips.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final chip in event.insightChips)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    chip,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DriftProTheme.primaryGreen,
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : onBot,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
              ),
              icon: const Icon(Icons.gavel, size: 18),
              label: const Text('BOT'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : onArchive,
              icon: Icon(
                event.isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
                size: 18,
              ),
              label: Text(event.isArchived ? 'Hent fra arkiv' : 'Arkiver'),
            ),
          ],
        ),
      ],
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }
}

class _SidebarList extends StatelessWidget {
  const _SidebarList({
    required this.events,
    required this.onSelect,
    required this.onRefresh,
  });

  final List<VisionEvent> events;
  final ValueChanged<VisionEvent> onSelect;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Neste klipp',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: events.isEmpty
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Text(
                          'Ingen flere videoklipp i denne fanen.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    itemCount: events.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 18),
                    itemBuilder: (context, i) {
                      final e = events[i];
                      return _SidebarTile(
                        event: e,
                        onTap: () => onSelect(e),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({required this.event, required this.onTap});

  final VisionEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time =
        DateFormat('dd.MM HH:mm').format(event.occurredAt.toLocal());
    final duration = event.clipDurationLabel ?? 'VIDEO';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 160,
              height: 90,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Colors.grey.shade900,
                    child: event.dropboxImageUrl.isNotEmpty
                        ? Image.network(
                            event.dropboxImageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.play_circle_outline,
                              color: Colors.white54,
                            ),
                          )
                        : const Icon(Icons.play_circle_outline,
                            color: Colors.white54),
                  ),
                  const Center(
                    child: Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 28),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        duration,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.violationSummary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  time,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.event, required this.onTap});

  final VisionEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time =
        DateFormat('dd.MM.yyyy HH:mm').format(event.occurredAt.toLocal());
    final duration = event.clipDurationLabel ?? 'VIDEO';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: Colors.grey.shade900,
                      child: event.dropboxImageUrl.isNotEmpty
                          ? Image.network(
                              event.dropboxImageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.videocam_outlined,
                                    color: Colors.white54, size: 40),
                              ),
                            )
                          : const Center(
                              child: Icon(Icons.videocam_outlined,
                                  color: Colors.white54, size: 40),
                            ),
                    ),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                    if (!event.isViewed)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: DriftProTheme.primaryGreen,
                            borderRadius: BorderRadius.circular(6),
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
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          duration,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              event.violationSummary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
