import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/partner_deduction_templates.dart';
import '../../../core/services/partner/partner_deduction_service.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/vision/vision_camera_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/vision_camera.dart';

/// Fullskjerm studio for sorteringsklipp — spiller, innsikt, arkiv og BOT.
Future<VisionEvent?> openWasteSortingStudio(
  BuildContext context, {
  required VisionEvent event,
  required List<VisionEvent> playlist,
}) {
  return Navigator.of(context).push<VisionEvent>(
    PageRouteBuilder(
      opaque: true,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => WasteSortingStudio(
        initial: event,
        playlist: playlist,
      ),
      transitionsBuilder: (_, anim, __, child) {
        return FadeTransition(opacity: anim, child: child);
      },
    ),
  );
}

Future<bool?> showWasteBotSheet(
  BuildContext context, {
  required VisionEvent event,
  String? companyId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WasteBotSheet(event: event, companyId: companyId),
  );
}

class WasteSortingStudio extends StatefulWidget {
  const WasteSortingStudio({
    super.key,
    required this.initial,
    required this.playlist,
  });

  final VisionEvent initial;
  final List<VisionEvent> playlist;

  @override
  State<WasteSortingStudio> createState() => _WasteSortingStudioState();
}

class _WasteSortingStudioState extends State<WasteSortingStudio> {
  late VisionEvent _event;
  late List<VisionEvent> _playlist;
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _busy = false;
  String? _error;
  String? _playableUrl;
  bool _showChrome = true;
  Timer? _hideChrome;

  @override
  void initState() {
    super.initState();
    _event = widget.initial;
    _playlist = List.of(widget.playlist);
    _boot();
  }

  @override
  void dispose() {
    _hideChrome?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    // Ikke merk som sett ved åpning — kun når bruker går videre.
    await _loadVideo(_event);
    _scheduleHideChrome();
  }

  Future<void> _loadVideo(VisionEvent event) async {
    setState(() {
      _ready = false;
      _error = null;
      _playableUrl = null;
    });
    await _controller?.dispose();
    _controller = null;

    final fresh =
        await VisionCameraService.instance.resolveEventMediaLink(event.id);
    String? url;
    if (fresh != null && !fresh.isImage && fresh.url.startsWith('http')) {
      url = fresh.url;
    } else if (event.videoDropboxPath != null) {
      final byPath = await VisionCameraService.instance
          .resolveDropboxPathLink(event.videoDropboxPath!);
      if (byPath != null &&
          !byPath.isImage &&
          byPath.url.startsWith('http')) {
        url = byPath.url;
      }
    }
    url ??= event.videoUrl;

    if (url == null || url.isEmpty || !url.startsWith('http')) {
      if (mounted) {
        setState(() =>
            _error = 'Ingen videofil — kun MP4-klipp kan spilles her.');
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
        _controller = c;
        _playableUrl = url;
        _ready = true;
      });
      c.addListener(() {
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Kunne ikke spille video: $e');
      }
    }
  }

  void _scheduleHideChrome() {
    _hideChrome?.cancel();
    _hideChrome = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _showChrome = false);
      }
    });
  }

  void _toggleChrome() {
    setState(() => _showChrome = !_showChrome);
    if (_showChrome) _scheduleHideChrome();
  }

  void _seekBy(Duration delta) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final next = c.value.position + delta;
    final dur = c.value.duration;
    final clamped = next < Duration.zero
        ? Duration.zero
        : (next > dur ? dur : next);
    c.seekTo(clamped);
    _scheduleHideChrome();
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
      _scheduleHideChrome();
    }
    setState(() {});
  }

  int get _index => _playlist.indexWhere((e) => e.id == _event.id);

  Future<void> _openSibling(int delta) async {
    final i = _index;
    if (i < 0) return;
    final next = i + delta;
    if (next < 0 || next >= _playlist.length) return;
    final previous = _event;
    final upcoming = _playlist[next];
    setState(() => _event = upcoming);
    // Merk forrige som sett når man bytter klipp.
    if (!previous.isViewed) {
      try {
        final updated = await VisionCameraService.instance
            .markSortingEventViewed(previous.id);
        if (mounted) {
          final idx = _playlist.indexWhere((e) => e.id == updated.id);
          if (idx >= 0) _playlist[idx] = updated;
        }
      } catch (_) {}
    }
    await _loadVideo(_event);
  }

  Future<void> _archive({required bool archived}) async {
    setState(() => _busy = true);
    try {
      final updated = await VisionCameraService.instance.setSortingEventArchived(
        _event.id,
        archived: archived,
      );
      if (!mounted) return;
      setState(() {
        _event = updated;
        final i = _playlist.indexWhere((e) => e.id == updated.id);
        if (i >= 0) _playlist[i] = updated;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(archived ? 'Arkivert' : 'Hentet tilbake fra arkiv'),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: DriftProTheme.error),
        );
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett klipp?'),
        content: const Text(
          'Klippet skjules fra feeden (status «avvist»). '
          'Selve filen i Dropbox slettes ikke automatisk.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.error),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final updated =
          await VisionCameraService.instance.softDeleteSortingEvent(_event.id);
      if (!mounted) return;
      Navigator.pop(context, updated);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: DriftProTheme.error),
        );
      }
    }
  }

  Future<void> _saveExternally() async {
    final url = _playableUrl ?? _event.videoUrl ?? _event.dropboxImageUrl;
    if (url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _openBot() async {
    await _controller?.pause();
    if (!mounted) return;
    final result = await showWasteBotSheet(
      context,
      event: _event,
      companyId: '00000000-0000-0000-0000-000000000000',
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'BOT lagret under Bot/Trekk. Partner får varsel med video, beløp og kommentar.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final progress = (c != null &&
            c.value.isInitialized &&
            c.value.duration.inMilliseconds > 0)
        ? c.value.position.inMilliseconds / c.value.duration.inMilliseconds
        : 0.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: _toggleChrome,
              onDoubleTapDown: (d) {
                final w = MediaQuery.sizeOf(context).width;
                if (d.localPosition.dx < w / 2) {
                  _seekBy(const Duration(seconds: -10));
                } else {
                  _seekBy(const Duration(seconds: 10));
                }
              },
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
                    : !_ready || c == null
                        ? const CircularProgressIndicator(color: Colors.white)
                        : AspectRatio(
                            aspectRatio: c.value.aspectRatio == 0
                                ? 16 / 9
                                : c.value.aspectRatio,
                            child: VideoPlayer(c),
                          ),
              ),
            ),
            if (_showChrome) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    top: MediaQuery.paddingOf(context).top + 4,
                    left: 4,
                    right: 8,
                    bottom: 12,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context, _event),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _event.violationSummary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              DateFormat('dd.MM.yyyy HH:mm:ss')
                                  .format(_event.occurredAt.toLocal()),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!_event.isViewed)
                        Container(
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
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    24,
                    12,
                    MediaQuery.paddingOf(context).bottom + 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.92),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final chip in _event.insightChips)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white24,
                                ),
                              ),
                              child: Text(
                                chip,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _controller != null
                            ? 'Systemet flagget dette som avvik. '
                                'Dobbelttrykk venstre/høyre = ±10 sek.'
                            : 'Kun stillbilde tilgjengelig for dette klippet '
                                '(video lastes når Windows-worker er oppdatert).',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                      if (_controller != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () =>
                                  _seekBy(const Duration(seconds: -10)),
                              icon: const Icon(Icons.replay_10,
                                  color: Colors.white, size: 28),
                            ),
                            IconButton(
                              onPressed: _togglePlay,
                              icon: Icon(
                                (c?.value.isPlaying ?? false)
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_filled,
                                color: Colors.white,
                                size: 44,
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  _seekBy(const Duration(seconds: 10)),
                              icon: const Icon(Icons.forward_10,
                                  color: Colors.white, size: 28),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Column(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: progress.clamp(0.0, 1.0),
                                      minHeight: 4,
                                      backgroundColor: Colors.white24,
                                      color: DriftProTheme.primaryGreen,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _fmt(c?.value.position ??
                                            Duration.zero),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                                      Text(
                                        _fmt(c?.value.duration ??
                                            Duration.zero),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Forrige',
                            onPressed: _index > 0 ? () => _openSibling(-1) : null,
                            icon: const Icon(Icons.skip_previous,
                                color: Colors.white),
                          ),
                          IconButton(
                            tooltip: 'Neste',
                            onPressed: _index >= 0 &&
                                    _index < _playlist.length - 1
                                ? () => _openSibling(1)
                                : null,
                            icon: const Icon(Icons.skip_next,
                                color: Colors.white),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Lagre / åpne',
                            onPressed: _saveExternally,
                            icon: const Icon(Icons.download_outlined,
                                color: Colors.white),
                          ),
                          IconButton(
                            tooltip: _event.isArchived
                                ? 'Hent fra arkiv'
                                : 'Arkiver',
                            onPressed: _busy
                                ? null
                                : () =>
                                    _archive(archived: !_event.isArchived),
                            icon: Icon(
                              _event.isArchived
                                  ? Icons.unarchive_outlined
                                  : Icons.archive_outlined,
                              color: Colors.white,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Slett',
                            onPressed: _busy ? null : _delete,
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.white70),
                          ),
                          const SizedBox(width: 4),
                          FilledButton.icon(
                            onPressed: _busy ? null : _openBot,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFE53935),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                            ),
                            icon: const Icon(Icons.gavel, size: 18),
                            label: const Text(
                              'BOT',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
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

class _WasteBotSheet extends StatefulWidget {
  const _WasteBotSheet({required this.event, this.companyId});

  final VisionEvent event;
  final String? companyId;

  @override
  State<_WasteBotSheet> createState() => _WasteBotSheetState();
}

class _WasteBotSheetState extends State<_WasteBotSheet> {
  static const _maviCompanyId = '00000000-0000-0000-0000-000000000000';

  List<Partner> _partners = [];
  Partner? _partner;
  final _amountCtrl = TextEditingController(text: '500');
  final _nameCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();
  bool _sms = true;
  bool _push = true;
  bool _loading = true;
  bool _sending = false;
  String _query = '';
  String? _videoLink;
  String? _resolvedCompanyId;

  @override
  void initState() {
    super.initState();
    _commentCtrl.text = widget.event.violationSummary;
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _nameCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<String> _resolveCompanyId() async {
    if (widget.companyId != null && widget.companyId!.isNotEmpty) {
      return widget.companyId!;
    }
    // Søppelsortering hører til MAVI — ikke Demo (der Dropbox-OAuth kan ligge).
    return _maviCompanyId;
  }

  Future<void> _load() async {
    try {
      final companyId = await _resolveCompanyId();
      _resolvedCompanyId = companyId;

      final media = await VisionCameraService.instance
          .resolveEventMediaLink(widget.event.id);
      final link = media?.url ??
          widget.event.videoUrl ??
          widget.event.dropboxImageUrl;
      _videoLink = (link.isNotEmpty) ? link : null;

      if (mounted) {
        _commentCtrl.text = widget.event.violationSummary;
      }

      var partners = await PartnerService.fetchPartners(
        companyId: companyId,
        activeOnly: true,
      );
      // Fallback: hvis Demo-profil og tom liste, prøv MAVI.
      if (partners.isEmpty && companyId != _maviCompanyId) {
        partners = await PartnerService.fetchPartners(
          companyId: _maviCompanyId,
          activeOnly: true,
        );
        if (partners.isNotEmpty) _resolvedCompanyId = _maviCompanyId;
      }

      if (!mounted) return;
      setState(() {
        _partners = partners..sort((a, b) => a.name.compareTo(b.name));
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke laste partnere: $e')),
        );
      }
    }
  }

  List<Partner> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _partners;
    return _partners
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            (p.orgNumber?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  Future<void> _send({required bool notifyOnly}) async {
    final partner = _partner;
    if (partner == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg partner')),
      );
      return;
    }
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Oppgi gyldig beløp')),
      );
      return;
    }
    if (!_sms && !_push && !notifyOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg SMS og/eller push-varsel')),
      );
      return;
    }

    final template = kPartnerDeductionTemplates.firstWhere(
      (t) => t.id == 'waste_sorting',
      orElse: () => kPartnerDeductionTemplates.first,
    );
    final companyId = _resolvedCompanyId ?? await _resolveCompanyId();

    setState(() => _sending = true);
    final displayName = _nameCtrl.text.trim();
    final userComment = _commentCtrl.text.trim();
    final path = widget.event.videoDropboxPath;
    final comment = [
      'Feilsortering (kamera): ${widget.event.violationSummary}',
      'Beløp: ${amount.toStringAsFixed(0)} kr',
      if (displayName.isNotEmpty) 'Kontakt/ref: $displayName',
      if (userComment.isNotEmpty) 'Kommentar: $userComment',
      if (_videoLink != null) 'Video: $_videoLink',
      if (path != null && path.isNotEmpty) 'Dropbox: $path',
    ].join('\n');

    try {
      // 1) Opprett sak uten varsel først (så den dukker opp under Trekk).
      final result = await PartnerDeductionService.createCase(
        companyId: companyId,
        partner: partner,
        template: template,
        amountNok: amount,
        comment: comment,
        notifySms: false,
        notifyEmail: false,
        notifyPush: false,
      );

      if (!result.success || result.caseRow == null) {
        if (mounted) {
          setState(() => _sending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.error ?? 'BOT feilet'),
              backgroundColor: DriftProTheme.error,
            ),
          );
        }
        return;
      }

      final caseRow = result.caseRow!;

      // 2) Knytt sorteringsvideo som bevis (partner ser den i portalen).
      if (path != null && path.isNotEmpty) {
        final dropboxPath = path.replaceFirst('dropbox://', '');
        try {
          await SupabaseService.client.rpc(
            'add_partner_deduction_evidence',
            params: {
              'p_case_id': caseRow.id,
              'p_storage_ref': dropboxPath.startsWith('dropbox://')
                  ? dropboxPath
                  : 'dropbox://$dropboxPath',
              'p_storage_provider': 'dropbox',
              'p_file_name': 'sorting_clip.mp4',
              'p_mime_type': 'video/mp4',
              'p_media_type': 'video',
              'p_file_size_bytes': 0,
              'p_dropbox_path': dropboxPath,
            },
          );
        } catch (e) {
          // Fortsett — sak finnes; video-lenke er i kommentaren.
          debugPrint('waste bot evidence: $e');
        }
      }

      // 3) Send SMS/push etter at bevis er på plass.
      if (!notifyOnly && (_sms || _push)) {
        await PartnerDeductionService.resendNotification(
          caseId: caseRow.id,
          notifySms: _sms,
          notifyEmail: false,
          notifyPush: _push,
        );
        await PartnerDeductionService.flushOutbox();
      }

      if (!mounted) return;
      setState(() => _sending = false);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('BOT feilet: $e'),
            backgroundColor: DriftProTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      margin: const EdgeInsets.only(top: 48),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: _loading
            ? const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Send BOT til partner',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Partner får varsel med beløp, kommentar og video. '
                      'Saken dukker opp under Bot/Trekk — de kan se video og arkivere.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 13,
                      ),
                    ),
                    if (_partners.isEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Ingen partnere funnet for denne bedriften. '
                        'Sjekk at du er innlogget på MAVI.',
                        style: TextStyle(
                          color: Colors.orange.shade300,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: _darkDeco('Søk partner'),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final p = _filtered[i];
                          final selected = _partner?.id == p.id;
                          return ListTile(
                            dense: true,
                            selected: selected,
                            selectedTileColor:
                                DriftProTheme.primaryGreen.withValues(alpha: 0.2),
                            title: Text(
                              p.name,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              p.orgNumber ?? '',
                              style: const TextStyle(color: Colors.white54),
                            ),
                            onTap: () => setState(() => _partner = p),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: _darkDeco('Navn / referanse (valgfritt)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: _darkDeco('Beløp (kr)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _commentCtrl,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: _darkDeco('Melding / beskrivelse'),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('SMS',
                          style: TextStyle(color: Colors.white)),
                      value: _sms,
                      activeThumbColor: DriftProTheme.primaryGreen,
                      onChanged: (v) => setState(() => _sms = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Push-varsel',
                          style: TextStyle(color: Colors.white)),
                      value: _push,
                      activeThumbColor: DriftProTheme.primaryGreen,
                      onChanged: (v) => setState(() => _push = v),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _sending
                                ? null
                                : () => _send(notifyOnly: true),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white38),
                            ),
                            child: const Text('Bare lagre BOT'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _sending
                                ? null
                                : () => _send(notifyOnly: false),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFE53935),
                            ),
                            child: _sending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Send BOT'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  InputDecoration _darkDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: DriftProTheme.primaryGreen),
      ),
    );
  }
}
