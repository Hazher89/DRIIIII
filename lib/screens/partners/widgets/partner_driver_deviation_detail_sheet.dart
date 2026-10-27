import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../../core/services/partner/partner_driver_deviation_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner_driver_deviation.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Profesjonell detaljvisning for sjåføravvik (kommentar, bilder, inline video).
Future<void> showPartnerDriverDeviationDetail(
  BuildContext context,
  PartnerDriverDeviation item,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => PartnerDriverDeviationDetailSheet(item: item),
  );
}

class _ResolvedMedia {
  const _ResolvedMedia({this.url, this.bytes, this.error});

  final String? url;
  final Uint8List? bytes;
  final String? error;

  bool get ok =>
      (url != null && url!.isNotEmpty) || (bytes != null && bytes!.isNotEmpty);
}

class PartnerDriverDeviationDetailSheet extends StatefulWidget {
  const PartnerDriverDeviationDetailSheet({super.key, required this.item});

  final PartnerDriverDeviation item;

  @override
  State<PartnerDriverDeviationDetailSheet> createState() =>
      _PartnerDriverDeviationDetailSheetState();
}

class _PartnerDriverDeviationDetailSheetState
    extends State<PartnerDriverDeviationDetailSheet> {
  final Map<String, _ResolvedMedia> _resolved = {};
  bool _loadingMedia = true;

  @override
  void initState() {
    super.initState();
    _resolveMedia();
  }

  Future<void> _resolveMedia() async {
    final refs = [...widget.item.imageUrls, ...widget.item.videoUrls];
    if (refs.isEmpty) {
      setState(() => _loadingMedia = false);
      return;
    }
    for (final ref in refs) {
      try {
        final hit = await PartnerDriverDeviationService.resolveMedia(ref);
        _resolved[ref] = _ResolvedMedia(url: hit.url, bytes: hit.bytes);
      } catch (e) {
        _resolved[ref] = _ResolvedMedia(error: e.toString());
      }
      if (mounted) setState(() {});
    }
    if (mounted) setState(() => _loadingMedia = false);
  }

  void _openImageFullscreen(_ResolvedMedia media) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: media.bytes != null
                    ? Image.memory(media.bytes!, fit: BoxFit.contain)
                    : Image.network(
                        media.url!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.broken_image,
                          color: Colors.white54,
                          size: 48,
                        ),
                      ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final fu = item.freightUnit?.trim().isNotEmpty == true
        ? item.freightUnit!.trim()
        : (item.customerRef?.trim() ?? '');
    final order = item.orderRef?.trim() ?? '';
    final scheme = Theme.of(context).colorScheme;
    final maxH = MediaQuery.sizeOf(context).height * 0.94;
    final imageCount = item.imageUrls.length;
    final videoCount = item.videoUrls.length;

    return SizedBox(
      height: maxH,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.customerName?.trim().isNotEmpty == true
                            ? item.customerName!.trim()
                            : 'Sjåføravvik',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Rute ${DateFormat('d. MMMM yyyy', 'nb').format(item.routeDate)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      Text(
                        'Meldt ${DateFormat('d.M.yyyy HH:mm', 'nb').format(item.createdAt.toLocal())}'
                        ' · ${item.reporterLabel}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Lukk',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (fu.isNotEmpty)
                      _chip('Nr $fu', Icons.badge_outlined),
                    if (order.isNotEmpty)
                      _chip('Ordre $order', Icons.receipt_long_outlined),
                    if ((item.customerPhone ?? '').trim().isNotEmpty)
                      _chip(
                        item.customerPhone!.trim(),
                        Icons.phone_outlined,
                      ),
                    if (imageCount > 0)
                      _chip(
                        '$imageCount bilde${imageCount == 1 ? '' : 'r'}',
                        Icons.photo_outlined,
                      ),
                    if (videoCount > 0)
                      _chip(
                        '$videoCount video${videoCount == 1 ? '' : 'er'}',
                        Icons.videocam_outlined,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Kommentar',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    item.comment,
                    style: const TextStyle(height: 1.45, fontSize: 15),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Dokumentasjon',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                if (_loadingMedia && _resolved.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: DriftProLoadingCenter(),
                  )
                else if (item.imageUrls.isEmpty && item.videoUrls.isEmpty)
                  Text(
                    'Ingen bilder eller video er lagt ved dette avviket.',
                    style: TextStyle(color: Colors.grey.shade600),
                  )
                else ...[
                  if (item.imageUrls.isNotEmpty) ...[
                    const Text(
                      'Bilder',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < item.imageUrls.length; i++) ...[
                      _ImageTile(
                        index: i + 1,
                        total: item.imageUrls.length,
                        media: _resolved[item.imageUrls[i]],
                        loading: _loadingMedia &&
                            !_resolved.containsKey(item.imageUrls[i]),
                        onOpen: (m) => _openImageFullscreen(m),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                  if (item.videoUrls.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Video',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < item.videoUrls.length; i++) ...[
                      _InlineVideoTile(
                        label: item.videoUrls.length == 1
                            ? 'Video'
                            : 'Video ${i + 1}',
                        media: _resolved[item.videoUrls[i]],
                        loading: _loadingMedia &&
                            !_resolved.containsKey(item.videoUrls[i]),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, IconData icon, {Color? color}) {
    final c = color ?? Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.index,
    required this.total,
    required this.media,
    required this.loading,
    required this.onOpen,
  });

  final int index;
  final int total;
  final _ResolvedMedia? media;
  final bool loading;
  final void Function(_ResolvedMedia media) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          total > 1 ? 'Bilde $index av $total' : 'Bilde',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Material(
              color: Colors.grey.shade200,
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : media == null || !media!.ok
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              media?.error != null
                                  ? 'Bildet kunne ikke lastes'
                                  : 'Mangler bilde',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                        )
                      : InkWell(
                          onTap: () => onOpen(media!),
                          child: media!.bytes != null
                              ? Image.memory(
                                  media!.bytes!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                )
                              : Image.network(
                                  media!.url!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (_, _, _) => Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.grey.shade600,
                                      size: 40,
                                    ),
                                  ),
                                ),
                        ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InlineVideoTile extends StatefulWidget {
  const _InlineVideoTile({
    required this.label,
    required this.media,
    required this.loading,
  });

  final String label;
  final _ResolvedMedia? media;
  final bool loading;

  @override
  State<_InlineVideoTile> createState() => _InlineVideoTileState();
}

class _InlineVideoTileState extends State<_InlineVideoTile> {
  VideoPlayerController? _controller;
  bool _ready = false;
  String? _error;
  String? _boundTo;

  @override
  void didUpdateWidget(covariant _InlineVideoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeInit();
  }

  @override
  void initState() {
    super.initState();
    _maybeInit();
  }

  void _maybeInit() {
    final media = widget.media;
    if (media == null || !media.ok) return;
    final url = media.url?.trim();
    if (url == null || url.isEmpty) {
      if (_boundTo == 'no-url') return;
      _boundTo = 'no-url';
      setState(() {
        _error = 'Video mangler avspillingslenke. Prøv å lukke og åpne igjen.';
        _controller = null;
        _ready = false;
      });
      return;
    }
    if (_boundTo == url) return;
    _boundTo = url;
    _controller?.dispose();
    _ready = false;
    _error = null;

    final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = ctrl;
    ctrl.addListener(() {
      if (mounted) setState(() {});
    });
    ctrl.initialize().then((_) {
      if (mounted && identical(_controller, ctrl)) {
        setState(() => _ready = true);
      }
    }).catchError((Object e) {
      if (mounted && identical(_controller, ctrl)) {
        setState(() => _error = 'Video kunne ikke spilles av');
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: _ready && _controller != null
                ? _controller!.value.aspectRatio
                : 16 / 9,
            child: ColoredBox(
              color: Colors.black,
              child: widget.loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : _error != null || widget.media == null || !widget.media!.ok
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _error ??
                                  widget.media?.error ??
                                  'Video kunne ikke lastes',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                        )
                      : !_ready || _controller == null
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            )
                          : Stack(
                              alignment: Alignment.center,
                              children: [
                                VideoPlayer(_controller!),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: VideoProgressIndicator(
                                    _controller!,
                                    allowScrubbing: true,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                      horizontal: 12,
                                    ),
                                    colors: const VideoProgressColors(
                                      playedColor: DriftProTheme.primaryGreen,
                                      bufferedColor: Colors.white24,
                                      backgroundColor: Colors.white12,
                                    ),
                                  ),
                                ),
                                Material(
                                  color: Colors.black45,
                                  shape: const CircleBorder(),
                                  child: IconButton(
                                    iconSize: 52,
                                    color: Colors.white,
                                    onPressed: () {
                                      setState(() {
                                        if (_controller!.value.isPlaying) {
                                          _controller!.pause();
                                        } else {
                                          _controller!.play();
                                        }
                                      });
                                    },
                                    icon: Icon(
                                      _controller!.value.isPlaying
                                          ? Icons.pause_circle_filled
                                          : Icons.play_circle_filled,
                                    ),
                                  ),
                                ),
                              ],
                            ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tomt resultat for CCC-søk — profesjonell melding.
class PartnerDriverDeviationEmptySearch extends StatelessWidget {
  const PartnerDriverDeviationEmptySearch({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Material(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.search_off_outlined, color: Colors.grey.shade600),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ingen avvik funnet',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Vi fant dessverre ingen sjåføravvik knyttet til «$query». '
                      'Dobbeltsjekk bilagsnummeret (starter med 2…) eller Freight Unit (starter med 4…).',
                      style: TextStyle(
                        height: 1.35,
                        color: Colors.grey.shade700,
                        fontSize: 13,
                      ),
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
