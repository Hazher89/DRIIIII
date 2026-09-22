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
    void add(String? p) {
      if (p == null || p.isEmpty) return;
      final n = p.replaceAll('\\', '/');
      // Kun Dropbox-stier — ikke lokale Windows-filer.
      if (!n.startsWith('/')) return;
      if (n.contains(':/')) return;
      if (n.contains('/captures/')) return;
      if (!paths.contains(n)) paths.add(n);
    }

    for (final p in s.dropboxPaths) {
      add(p);
    }
    add(s.dropboxVideoPath);
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
/// Etter svar fjernes klippet fra køen og neste lastes.
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
  late final List<String> _queue;
  late final int _totalStart;
  VideoPlayerController? _player;
  bool _ready = false;
  String? _error;
  bool _saving = false;
  String _zone = 'container_A_papp';

  @override
  void initState() {
    super.initState();
    _queue = List<String>.from(widget.clipPaths);
    _totalStart = _queue.length;
    _loadCurrent();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  String? get _path => _queue.isEmpty ? null : _queue.first;

  Future<void> _disposePlayer() async {
    final c = _player;
    _player = null;
    if (c != null) {
      try {
        await c.dispose();
      } catch (_) {}
    }
  }

  Future<void> _loadCurrent() async {
    setState(() {
      _ready = false;
      _error = null;
    });
    await _disposePlayer();

    final path = _path;
    if (path == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!path.startsWith('/')) {
      if (mounted) {
        setState(() => _error =
            'Video ble ikke lastet opp til Dropbox (kun lokal fil på jobb-PC).\n'
            'Trykk Hopp over, eller kjør opplæring på nytt.');
      }
      return;
    }

    final fresh = await VisionCameraService.instance.resolveDropboxPathLink(
      path,
      sessionId: widget.session.id,
    );
    final url = fresh?.url ??
        (path == widget.session.dropboxVideoPath
            ? widget.session.dropboxVideoUrl
            : null);
    if (url == null || !url.startsWith('http')) {
      if (mounted) {
        setState(() => _error =
            'Kunne ikke hente videolenke for denne filen.\n\n'
            'Sjekk Dropbox-kobling, eller trykk Hopp over.');
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
      if (mounted) {
        setState(() => _error =
            'Kunne ikke spille: $e\n\n'
            'Hopp over og merk neste, eller lag nytt opptak.');
      }
    }
  }

  Future<void> _advanceAfterAnswer() async {
    if (_queue.isEmpty) return;
    await _disposePlayer();
    setState(() {
      _queue.removeAt(0);
      _saving = false;
      _ready = false;
      _error = null;
    });
    if (_queue.isEmpty) {
      if (!mounted) return;
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
    await _loadCurrent();
  }

  Future<void> _skipUnplayable() async {
    if (_saving || _queue.isEmpty) return;
    await _advanceAfterAnswer();
  }

  Future<void> _answer(String label) async {
    if (_saving) return;
    final path = _path;
    if (path == null) return;
    setState(() => _saving = true);
    try {
      await VisionCameraService.instance.addLearnLabel(
        sessionId: widget.session.id,
        label: label,
        zone: _zone,
        note: 'clip:$path',
        reason: label == 'wrong' ? 'learn_demo_wrong' : 'learn_demo_correct',
      );
      if (!mounted) return;
      await _advanceAfterAnswer();
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
    final left = _queue.length;
    final done = _totalStart - left;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          left == 0
              ? 'Opplæring ferdig'
              : 'Opplæring ${done + 1} / $_totalStart · $left igjen',
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 20),
                            OutlinedButton(
                              onPressed: _saving ? null : _skipUnplayable,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Hopp over denne'),
                            ),
                          ],
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
                    'Svaret lagres med en gang — videoen forsvinner og neste kommer.',
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
                          onPressed: (_saving || _error != null)
                              ? null
                              : () => _answer('correct'),
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
                          onPressed: (_saving || _error != null)
                              ? null
                              : () => _answer('wrong'),
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
