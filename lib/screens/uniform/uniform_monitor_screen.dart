import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions/user_access.dart';
import '../../core/layout/mobile_shell_scaffold.dart';
import '../../core/routing/app_paths.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/vision/vision_camera_service.dart';
import '../../models/user_profile.dart';
import '../../models/vision_camera.dart';
import '../../widgets/driftpro_loading_indicator.dart';
import 'widgets/uniform_live_viewport.dart';
import 'widgets/uniform_violations_gallery.dart';

/// Live uniform-monitor: MAVI-logo på bryst + vernesko.
class UniformMonitorScreen extends StatefulWidget {
  const UniformMonitorScreen({super.key});

  @override
  State<UniformMonitorScreen> createState() => _UniformMonitorScreenState();
}

class _UniformMonitorScreenState extends State<UniformMonitorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<VisionCamera> _cameras = [];
  List<VisionEvent> _violations = [];
  String? _activeCameraId;
  Uint8List? _liveFrame;
  String? _liveError;
  bool _scanActive = false;
  int _scanPersons = 0;
  List<VisionFeedLine> _feedLines = [];
  bool _loading = true;
  bool _liveBusy = false;
  Timer? _liveTimer;
  Timer? _scanTimer;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(_onTabChanged);
    _bootstrap();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    if (_tabs.index == 1) unawaited(_refreshViolations());
  }

  Future<void> _refreshViolations() async {
    final events =
        await VisionCameraService.instance.fetchMonitorViolations();
    if (!mounted) return;
    setState(() {
      _violations = events;
    });
  }

  Future<void> _bootstrap() async {
    _profile = await SupabaseService.fetchCurrentUserProfile();
    await _reload();
    _startLivePolling();
  }

  void _startLivePolling() {
    _liveTimer?.cancel();
    _scanTimer?.cancel();
    if (!kIsWeb) {
      _liveTimer = Timer.periodic(const Duration(milliseconds: 380), (_) => _pollLive());
      unawaited(_pollLive());
    } else {
      // Web: video via iframe embed — ikke http-fetch (CORS).
      setState(() => _scanActive = true);
    }
    _scanTimer = Timer.periodic(const Duration(milliseconds: 600), (_) => _pollScan());
    unawaited(_pollScan());
  }

  void _onStreamReady() {
    if (!mounted) return;
    setState(() => _scanActive = true);
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final cameras = await VisionCameraService.instance.fetchUniformCameras();
      if (cameras.isEmpty) {
        final all = await VisionCameraService.instance.fetchCameras();
        _cameras = all.where((c) => c.enabled).toList();
      } else {
        _cameras = cameras;
      }
      final violations =
          await VisionCameraService.instance.fetchMonitorViolations();
      if (!mounted) return;
      setState(() {
        _violations = violations;
        _activeCameraId ??= _cameras.isNotEmpty ? _cameras.first.id : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke laste uniform-monitor: $e')),
      );
    }
  }

  Future<void> _pollLive() async {
    final camId = _activeCameraId;
    if (camId == null || _liveBusy || !mounted) return;
    _liveBusy = true;
    try {
      final result = await VisionCameraService.instance.fetchLiveFrame(camId);
      if (!mounted) return;
      if (result.ok) {
        setState(() {
          _liveFrame = result.bytes;
          _liveError = null;
          _scanActive = true;
        });
      } else if (_liveFrame == null && !kIsWeb) {
        setState(() => _liveError = 'Kobler til kamera…');
      }
    } catch (e) {
      if (mounted && _liveFrame == null && !kIsWeb) {
        setState(() => _liveError = 'Kobler til kamera…');
      }
    } finally {
      _liveBusy = false;
    }
  }

  Future<void> _pollScan() async {
    final scan = await VisionCameraService.instance.fetchMonitorScanStatus();
    final events =
        await VisionCameraService.instance.fetchMonitorViolations();
    final feed = await VisionCameraService.instance.fetchMonitorScanFeed();
    if (!mounted) return;
    setState(() {
      _violations = events;
      _feedLines = feed;
      if (scan != null) {
        _scanPersons = scan.persons;
        if (scan.active) _scanActive = true;
      } else if (_liveFrame != null) {
        _scanActive = true;
      }
    });
  }

  int get _bruddCount => _violations.length;

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _liveTimer?.cancel();
    _scanTimer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  bool get _canAdmin =>
      _profile?.access.canUniformMonitorAdmin == true ||
      _profile?.isSuperAdmin == true;

  @override
  Widget build(BuildContext context) {
    final access = UserAccess.of(_profile);
    if (access != null && !access.canUniformMonitor) {
      return Scaffold(
        appBar: AppBar(title: const Text('Uniform-monitor')),
        body: const Center(
          child: Text('Du har ikke tilgang til uniform-monitor.'),
        ),
      );
    }

    return MobileShellScaffold(
      title: 'Uniform-monitor',
      actions: [
        if (_canAdmin)
          IconButton(
            tooltip: 'Kameraer',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppPaths.moreVisionCameras),
          ),
        IconButton(
          tooltip: 'Oppdater',
          icon: const Icon(Icons.refresh),
          onPressed: () async {
            await _reload();
            await _refreshViolations();
            if (!kIsWeb) await _pollLive();
          },
        ),
      ],
      bottom: TabBar(
        controller: _tabs,
        tabs: [
          const Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam_outlined, size: 18),
                SizedBox(width: 6),
                Text('Live'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_outlined, size: 18),
                const SizedBox(width: 6),
                Text('Brudd ($_bruddCount)'),
              ],
            ),
          ),
        ],
      ),
      body: _loading
          ? const DriftProLoadingCenter()
          : ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: TabBarView(
                controller: _tabs,
                children: [
                  UniformLiveViewport(
                  cameras: _cameras,
                  activeCameraId: _activeCameraId,
                  liveFrame: _liveFrame,
                  liveError: kIsWeb ? null : _liveError,
                  scanPersons: _scanPersons,
                  scanActive: _scanActive,
                  sessionViolations: _bruddCount,
                  feedLines: _feedLines,
                  onCameraSelected: (id) {
                    setState(() {
                      _activeCameraId = id;
                      _liveFrame = null;
                      _liveError = null;
                    });
                    unawaited(_pollLive());
                  },
                  onRetry: () => unawaited(_pollLive()),
                  onStreamReady: _onStreamReady,
                ),
                UniformViolationsGallery(
                  violations: _violations,
                  onRefresh: _refreshViolations,
                ),
              ],
            ),
          ),
    );
  }
}
