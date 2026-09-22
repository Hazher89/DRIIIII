import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../core/services/vision/vision_camera_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/vision_camera.dart';

/// Læremodus: ta opp besøk → etter stopp merkes hver video riktig/feil én og én.
class WasteLearnPanel extends StatefulWidget {
  const WasteLearnPanel({
    super.key,
    required this.cameras,
    required this.canAdmin,
    required this.onChanged,
  });

  final List<VisionCamera> cameras;
  final bool canAdmin;
  final VoidCallback onChanged;

  @override
  State<WasteLearnPanel> createState() => _WasteLearnPanelState();
}

class _WasteLearnPanelState extends State<WasteLearnPanel> {
  bool _busy = false;
  List<VisionLearnSession> _sessions = [];
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _reloadSessions();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      _reloadSessions(silent: true);
      // Soft refresh kun når læremodus er aktiv (status/REC).
      final cam = _sortingCam;
      if (cam != null && cam.learnMode) {
        widget.onChanged();
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _reloadSessions({bool silent = false}) async {
    try {
      final sessions =
          await VisionCameraService.instance.fetchLearnSessions(limit: 20);
      if (!mounted) return;
      setState(() => _sessions = sessions);
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke laste lære-sessions: $e')),
        );
      }
    }
  }

  VisionCamera? get _sortingCam {
    final sorting = widget.cameras
        .where((c) => c.eventType == 'sorting_clip' && c.enabled)
        .toList();
    if (sorting.isEmpty) return null;
    return sorting.first;
  }

  List<String> _clipPaths(VisionLearnSession s) {
    final paths = <String>[];
    for (final p in s.dropboxPaths) {
      if (p.startsWith('/') && !paths.contains(p)) paths.add(p);
    }
    final main = s.dropboxVideoPath;
    if (main != null && main.startsWith('/') && !paths.contains(main)) {
      paths.add(main);
    }
    return paths;
  }

  Future<Set<String>> _labeledClipPaths(String sessionId) async {
    final labels =
        await VisionCameraService.instance.fetchLearnLabels(sessionId);
    final out = <String>{};
    for (final l in labels) {
      final n = l.note ?? '';
      if (n.startsWith('clip:')) {
        out.add(n.substring(5).split('\n').first.trim());
      }
    }
    return out;
  }

  Future<void> _toggle(VisionCamera cam) async {
    if (!widget.canAdmin || _busy) return;
    setState(() => _busy = true);
    try {
      if (cam.learnMode) {
        final session =
            await VisionCameraService.instance.stopLearnMode(cam.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                session.status == 'uploading' || session.status == 'ready'
                    ? 'Opplæring stoppet — venter på videoer…'
                    : 'Opplæring stoppet (${session.status})',
              ),
            ),
          );
        }
        widget.onChanged();
        await _reloadSessions();
        if (mounted) {
          await _waitAndReview(session.id);
        }
      } else {
        await VisionCameraService.instance.startLearnMode(cam.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Opplæring PÅ — gå til kameraet og kast både riktig og feil flere ganger. '
                'Hvert besøk blir en video.',
              ),
              duration: Duration(seconds: 6),
            ),
          );
        }
        widget.onChanged();
        await _reloadSessions();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: DriftProTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _waitAndReview(String sessionId) async {
    // Poll til ready (max ~3 min).
    VisionLearnSession? session;
    for (var i = 0; i < 36; i++) {
      session =
          await VisionCameraService.instance.fetchLearnSession(sessionId);
      if (session == null) return;
      if (session.isReady || session.status == 'failed') break;
      if (!mounted) return;
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    if (!mounted || session == null) return;
    if (session.status == 'failed') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(session.errorMessage ?? 'Opplasting feilet'),
          backgroundColor: DriftProTheme.error,
        ),
      );
      return;
    }
    await _openReview(session);
  }

  Future<void> _openReview(VisionLearnSession session) async {
    final paths = _clipPaths(session);
    if (paths.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ingen besøksvideoer ennå. Start opplæring, gå foran kameraet, kast, gå vekk — stopp igjen.',
            ),
          ),
        );
      }
      return;
    }
    final labeled = await _labeledClipPaths(session.id);
    final pending = paths.where((p) => !labeled.contains(p)).toList();
    if (pending.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alle videoer er allerede merket.')),
        );
      }
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _LearnReviewWizard(
          session: session,
          clipPaths: pending,
        ),
      ),
    );
    await _reloadSessions();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cam = _sortingCam;
    if (cam == null) return const SizedBox.shrink();

    final ready = _sessions.where((s) => s.isReady).take(8).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.school_outlined,
                  color: cam.learnMode
                      ? DriftProTheme.primaryGreen
                      : Colors.grey.shade700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Opplæring',
                    style: DriftProTheme.headingSm.copyWith(fontSize: 15),
                  ),
                ),
                if (widget.canAdmin)
                  Switch.adaptive(
                    value: cam.learnMode,
                    onChanged: _busy ? null : (_) => _toggle(cam),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              cam.learnMode
                  ? 'REC på jobb-PC. Kast riktig og feil flere ganger foran kameraet. Slå av når du er ferdig — da spør DriftPro om hver video.'
                  : 'Slå på, gå til kameraet og demonstrer riktig + feil. Etter stopp merker du én og én video.',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            if (cam.learnMode) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.fiber_manual_record,
                        size: 14, color: Color(0xFFE53935)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'REC · ${cam.name}'
                        '${cam.learnStartedAt != null ? ' · startet ${DateFormat('HH:mm').format(cam.learnStartedAt!.toLocal())}' : ''}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (widget.canAdmin)
                      TextButton(
                        onPressed: _busy ? null : () => _toggle(cam),
                        child: const Text('Stopp'),
                      ),
                  ],
                ),
              ),
            ],
            if (ready.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Merk opplæringsvideoer',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 6),
              ...ready.map(
                (s) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.videocam_outlined),
                  title: Text(
                    DateFormat('dd.MM HH:mm').format(s.startedAt.toLocal()),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${_clipPaths(s).length} video(er)'
                    '${s.durationSeconds != null ? ' · ${s.durationSeconds!.round()}s' : ''}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openReview(s),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Én og én video: «Var dette riktig eller feil?»
class _LearnReviewWizard extends StatefulWidget {
  const _LearnReviewWizard({
    required this.session,
    required this.clipPaths,
  });

  final VisionLearnSession session;
  final List<String> clipPaths;

  @override
  State<_LearnReviewWizard> createState() => _LearnReviewWizardState();
}

class _LearnReviewWizardState extends State<_LearnReviewWizard> {
  int _index = 0;
  VideoPlayerController? _player;
  bool _ready = false;
  String? _error;
  bool _saving = false;
  String _zone = 'container_A_papp';

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  String get _path => widget.clipPaths[_index];

  Future<void> _loadCurrent() async {
    setState(() {
      _ready = false;
      _error = null;
    });
    await _player?.dispose();
    _player = null;

    final fresh =
        await VisionCameraService.instance.resolveDropboxPathLink(_path);
    final url = fresh?.url;
    if (url == null || !url.startsWith('http')) {
      if (mounted) {
        setState(() => _error = 'Kunne ikke hente videolenke.');
      }
      return;
    }
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
      await c.setLooping(true);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _player = c;
        _ready = true;
      });
      c.addListener(() {
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Kunne ikke spille: $e');
    }
  }

  Future<void> _answer(String label) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await VisionCameraService.instance.addLearnLabel(
        sessionId: widget.session.id,
        label: label,
        zone: _zone,
        note: 'clip:$_path',
        reason: label == 'wrong' ? 'learn_demo_wrong' : 'learn_demo_correct',
      );
      if (!mounted) return;
      if (_index + 1 >= widget.clipPaths.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ferdig! Systemet lærer av svarene dine ved neste skanning.',
            ),
          ),
        );
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _index += 1;
        _saving = false;
      });
      await _loadCurrent();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: DriftProTheme.error),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.clipPaths.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Opplæring ${_index + 1} / $total'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      )
                    : !_ready || _player == null
                        ? const CircularProgressIndicator(color: Colors.white)
                        : AspectRatio(
                            aspectRatio: _player!.value.aspectRatio == 0
                                ? 16 / 9
                                : _player!.value.aspectRatio,
                            child: VideoPlayer(_player!),
                          ),
              ),
            ),
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Var dette riktig eller feil sortering?',
                    style: DriftProTheme.headingSm.copyWith(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Svaret lagres med en gang — systemet blir flinkere.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'container_A_papp',
                        label: Text('A papp'),
                      ),
                      ButtonSegment(
                        value: 'container_B_annet',
                        label: Text('B annet'),
                      ),
                    ],
                    selected: {_zone},
                    onSelectionChanged: (s) => setState(() => _zone = s.first),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving ? null : () => _answer('correct'),
                          style: FilledButton.styleFrom(
                            backgroundColor: DriftProTheme.primaryGreen,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          icon: const Icon(Icons.check),
                          label: const Text('RIKTIG'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving ? null : () => _answer('wrong'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE53935),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          icon: const Icon(Icons.close),
                          label: const Text('FEIL'),
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
    );
  }
}
