import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../core/services/vision/vision_camera_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/vision_camera.dart';

/// Læremodus: start/stopp kontinuerlig opptak + merk riktig/feil.
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
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      _reloadSessions(silent: true);
      widget.onChanged();
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
                    ? 'Læremodus stoppet — worker laster opp video'
                    : 'Læremodus stoppet (${session.status})',
              ),
            ),
          );
        }
      } else {
        await VisionCameraService.instance.startLearnMode(cam.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Læremodus PÅ — Windows-PC tar opp kontinuerlig',
              ),
            ),
          );
        }
      }
      widget.onChanged();
      await _reloadSessions();
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

  Future<void> _openLabel(VisionLearnSession session) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LearnLabelSheet(session: session),
    );
    await _reloadSessions();
  }

  @override
  Widget build(BuildContext context) {
    final cam = _sortingCam;
    if (cam == null) return const SizedBox.shrink();

    final ready = _sessions.where((s) => s.isReady).take(5).toList();

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
                    'Læremodus',
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
                  ? 'Tar opp kontinuerlig på jobb-PC. Slå av for å stoppe og merke.'
                  : 'Slå på for å ta opp hele tiden. Etter stopp merker du riktig/feil.',
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
                'Merk video',
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
                    '${s.chunkCount} del(er)'
                    '${s.durationSeconds != null ? ' · ${s.durationSeconds!.round()}s' : ''}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openLabel(s),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LearnLabelSheet extends StatefulWidget {
  const _LearnLabelSheet({required this.session});

  final VisionLearnSession session;

  @override
  State<_LearnLabelSheet> createState() => _LearnLabelSheetState();
}

class _LearnLabelSheetState extends State<_LearnLabelSheet> {
  VideoPlayerController? _player;
  bool _ready = false;
  String? _error;
  String _zone = 'container_A_papp';
  final _note = TextEditingController();
  List<VisionLearnLabel> _labels = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _note.dispose();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      _labels = await VisionCameraService.instance
          .fetchLearnLabels(widget.session.id);
    } catch (_) {}

    final path = widget.session.dropboxVideoPath ??
        (widget.session.dropboxPaths.isNotEmpty
            ? widget.session.dropboxPaths.last
            : null);
    String? url = widget.session.dropboxVideoUrl;
    if (path != null && path.startsWith('/')) {
      final fresh =
          await VisionCameraService.instance.resolveDropboxPathLink(path);
      if (fresh?.url != null) url = fresh!.url;
    }
    if (url == null || url.isEmpty) {
      if (mounted) {
        setState(() => _error = 'Ingen videolenke ennå — vent til opplasting er ferdig.');
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

  Future<void> _save(String label) async {
    setState(() => _saving = true);
    try {
      final pos = _player?.value.position.inMilliseconds;
      await VisionCameraService.instance.addLearnLabel(
        sessionId: widget.session.id,
        label: label,
        zone: _zone,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        timestampInVideoSec:
            pos == null ? null : pos / 1000.0,
      );
      _labels = await VisionCameraService.instance
          .fetchLearnLabels(widget.session.id);
      _note.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              label == 'correct' ? 'Lagret: RIKTIG' : 'Lagret: FEIL',
            ),
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: DriftProTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Merk lære-video',
                style: DriftProTheme.headingSm,
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('dd.MM.yyyy HH:mm')
                    .format(widget.session.startedAt.toLocal()),
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: Colors.black,
                    child: _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                          )
                        : !_ready || _player == null
                            ? const Center(
                                child: CircularProgressIndicator(
                                    color: Colors.white),
                              )
                            : VideoPlayer(_player!),
                  ),
                ),
              ),
              if (_ready && _player != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        final c = _player!;
                        if (c.value.isPlaying) {
                          c.pause();
                        } else {
                          c.play();
                        }
                        setState(() {});
                      },
                      icon: Icon(
                        _player!.value.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        color: DriftProTheme.primaryGreen,
                        size: 36,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Tid: ${_player!.value.position.inSeconds}s — '
                        'merking knyttes til denne posisjonen',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Text('Sone', style: TextStyle(color: Colors.grey.shade700)),
              const SizedBox(height: 6),
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
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Kommentar (valgfritt)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : () => _save('correct'),
                      style: FilledButton.styleFrom(
                        backgroundColor: DriftProTheme.primaryGreen,
                      ),
                      icon: const Icon(Icons.check),
                      label: const Text('Riktig'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : () => _save('wrong'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE53935),
                      ),
                      icon: const Icon(Icons.close),
                      label: const Text('Feil'),
                    ),
                  ),
                ],
              ),
              if (_labels.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'Lagrede merker (${_labels.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                ..._labels.map(
                  (l) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      l.label == 'correct' ? Icons.check_circle : Icons.cancel,
                      color: l.label == 'correct'
                          ? DriftProTheme.primaryGreen
                          : const Color(0xFFE53935),
                    ),
                    title: Text(
                      '${l.label == 'correct' ? 'Riktig' : 'Feil'}'
                      '${l.zone != null ? ' · ${l.zone}' : ''}',
                    ),
                    subtitle: Text(
                      [
                        if (l.timestampInVideoSec != null)
                          '@ ${l.timestampInVideoSec!.round()}s',
                        if (l.note != null && l.note!.isNotEmpty) l.note!,
                      ].join(' · '),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
