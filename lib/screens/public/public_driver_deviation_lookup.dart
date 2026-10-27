import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../core/services/partner/public_driver_deviation_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// CCC/butikk: søk sjåføravvik på /montering uten innlogging.
class PublicDriverDeviationLookup extends StatefulWidget {
  const PublicDriverDeviationLookup({super.key, this.initialQuery});

  /// Prefyll og søk direkte (f.eks. bilag skrevet i hovedchatten).
  final String? initialQuery;

  @override
  State<PublicDriverDeviationLookup> createState() =>
      _PublicDriverDeviationLookupState();
}

class _PublicDriverDeviationLookupState
    extends State<PublicDriverDeviationLookup> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  List<PublicDriverDeviationHit> _items = const [];
  bool _busy = false;
  String? _error;
  String? _hint;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery?.trim() ?? '';
    if (q.isNotEmpty) {
      _ctrl.text = q;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search();
      });
    }
  }

  @override
  void didUpdateWidget(covariant PublicDriverDeviationLookup oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.initialQuery?.trim() ?? '';
    final prev = oldWidget.initialQuery?.trim() ?? '';
    if (next.isNotEmpty && next != prev) {
      _ctrl.text = next;
      _search();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _hint = null;
      _searched = true;
    });
    try {
      final res = await PublicDriverDeviationService.search(q);
      if (!mounted) return;
      setState(() {
        _items = res.items;
        _hint = res.hint;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(PublicDriverDeviationHit hit) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PublicDeviationDetail(hit: hit),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Leveringsavvik',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Søk med kundenavn, telefon, ordre (21…/22…/60…) '
                'eller kundenummer (39…/41…).',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        hintText: 'Hansen · tlf · 21… · 41…',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _search,
                    style: FilledButton.styleFrom(
                      backgroundColor: DriftProTheme.primaryGreen,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Søk'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _busy && _items.isEmpty
              ? const DriftProLoadingCenter()
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Kunne ikke søke: $_error',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : !_searched
                      ? _EmptyIntro()
                      : _items.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Text(
                                  _hint ??
                                      'Ingen avvik fant for «${_ctrl.text.trim()}».',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                              itemCount: _items.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) => _HitCard(
                                hit: _items[i],
                                onTap: () => _open(_items[i]),
                              ),
                            ),
        ),
      ],
    );
  }
}

class _EmptyIntro extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        Icon(Icons.photo_library_outlined, size: 48, color: Colors.grey.shade400),
        const SizedBox(height: 14),
        Text(
          'Finn dokumentasjon på leveringen',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Når sjåfør har meldt avvik på en kunde, kan du søke opp '
          'navn, telefon, ordre (21/22/60) eller kundenummer (39/41).',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.4, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

class _HitCard extends StatelessWidget {
  const _HitCard({required this.hit, required this.onTap});

  final PublicDriverDeviationHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bilag = hit.orderRef?.trim() ?? '';
    final fu = hit.freightUnit?.trim().isNotEmpty == true
        ? hit.freightUnit!.trim()
        : (hit.customerRef?.trim() ?? '');
    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hit.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (hit.mediaCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${hit.mediaCount} media',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  DateFormat('d. MMM yyyy', 'nb').format(hit.routeDate),
                  if (fu.isNotEmpty) 'Nr $fu',
                  if (bilag.isNotEmpty) 'Ordre $bilag',
                  if ((hit.customerPhone ?? '').trim().isNotEmpty)
                    hit.customerPhone!.trim(),
                ].join(' · '),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hit.comment,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.35, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                'Åpne detaljer →',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: DriftProTheme.primaryGreen,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublicDeviationDetail extends StatelessWidget {
  const _PublicDeviationDetail({required this.hit});

  final PublicDriverDeviationHit hit;

  @override
  Widget build(BuildContext context) {
    final bilag = hit.orderRef?.trim() ?? '';
    final fu = hit.freightUnit?.trim().isNotEmpty == true
        ? hit.freightUnit!.trim()
        : (hit.customerRef?.trim() ?? '');
    final maxH = MediaQuery.sizeOf(context).height * 0.92;

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
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hit.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Rute ${DateFormat('d. MMMM yyyy', 'nb').format(hit.routeDate)}'
                        ' · meldt ${DateFormat('d.M.yyyy HH:mm', 'nb').format(hit.createdAt.toLocal())}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (fu.isNotEmpty) _chip('Nr $fu', Icons.badge_outlined),
                    if (bilag.isNotEmpty)
                      _chip('Ordre $bilag', Icons.receipt_long),
                    if ((hit.customerPhone ?? '').trim().isNotEmpty)
                      _chip(
                        hit.customerPhone!.trim(),
                        Icons.phone_outlined,
                      ),
                    if ((hit.reporterName ?? '').trim().isNotEmpty)
                      _chip(hit.reporterName!.trim(), Icons.person_outline),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Kommentar',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    hit.comment,
                    style: const TextStyle(height: 1.45, fontSize: 15),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Bilder & video',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
                const SizedBox(height: 10),
                if (hit.images.isEmpty && hit.videos.isEmpty)
                  Text(
                    hit.mediaIncomplete
                        ? 'Vedlegg kunne ikke hentes akkurat nå. Prøv søket på nytt.'
                        : 'Ingen bilder eller video er lagt ved.',
                    style: TextStyle(color: Colors.grey.shade600),
                  )
                else ...[
                  for (final url in hit.images) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: Colors.grey.shade200,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  for (var i = 0; i < hit.videos.length; i++) ...[
                    _InlineVideoPlayer(
                      url: hit.videos[i],
                      label: hit.videos.length == 1
                          ? 'Video'
                          : 'Video ${i + 1}',
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (hit.mediaIncomplete)
                    Text(
                      'Noen vedlegg mangler (f.eks. lagret eksternt).',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade800,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.blueGrey.shade700),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: Colors.blueGrey.shade800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineVideoPlayer extends StatefulWidget {
  const _InlineVideoPlayer({required this.url, required this.label});

  final String url;
  final String label;

  @override
  State<_InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<_InlineVideoPlayer> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    _controller.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e.toString());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: _ready ? _controller.value.aspectRatio : 16 / 9,
            child: ColoredBox(
              color: Colors.black,
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Video kunne ikke spilles av',
                          style: TextStyle(color: Colors.grey.shade300),
                        ),
                      ),
                    )
                  : !_ready
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : Stack(
                          alignment: Alignment.center,
                          children: [
                            VideoPlayer(_controller),
                            Material(
                              color: Colors.black45,
                              shape: const CircleBorder(),
                              child: IconButton(
                                iconSize: 48,
                                color: Colors.white,
                                onPressed: () {
                                  setState(() {
                                    if (_controller.value.isPlaying) {
                                      _controller.pause();
                                    } else {
                                      _controller.play();
                                    }
                                  });
                                },
                                icon: Icon(
                                  _controller.value.isPlaying
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
