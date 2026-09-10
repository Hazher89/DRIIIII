import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/route_pdf_bytes_cache.dart';
import '../../../models/partner/partner_links.dart';

/// Felles pan for alle SAP Trip Overview-miniatyrer (AUTO MASS / Biler).
///
/// Hold inne og dra på én rute → alle forhåndsvisninger flytter live.
class RoutePdfThumbPanController extends ChangeNotifier {
  RoutePdfThumbPanController._();
  static final RoutePdfThumbPanController instance =
      RoutePdfThumbPanController._();

  /// Standard: litt mot venstre så strekkode + sjåførnavn synes.
  static const Offset defaultPan = Offset(-0.22, -0.02);

  Offset _pan = defaultPan;

  /// Normalized −1…1. Negativ dx = mer av venstre side (sjåfør/strekkode).
  Offset get pan => _pan;

  void setPan(Offset o) {
    final next = Offset(
      o.dx.clamp(-0.55, 0.55),
      o.dy.clamp(-0.45, 0.45),
    );
    if (next == _pan) return;
    _pan = next;
    notifyListeners();
  }

  void nudge(Offset delta) => setPan(_pan + delta);

  void reset() => setPan(defaultPan);
}

/// Miniatyr av første PDF-side — brukes i rute-kø før publisering.
class PartnerRoutePdfThumbnail extends StatefulWidget {
  final PartnerRouteShare? share;
  final Uint8List? bytes;
  final String? driverLabel;
  final double? height;
  final VoidCallback? onTapOpen;
  /// true = hele forsiden synlig (contain), false = fyller kort (cover).
  final bool showFullPage;
  /// Zoom inn øverst på forsiden (strekkode, dato, sjåfør på SAP Trip Overview).
  final bool zoomTripHeader;

  const PartnerRoutePdfThumbnail({
    super.key,
    this.share,
    this.bytes,
    this.driverLabel,
    this.height,
    this.onTapOpen,
    this.showFullPage = true,
    this.zoomTripHeader = false,
  });

  @override
  State<PartnerRoutePdfThumbnail> createState() =>
      _PartnerRoutePdfThumbnailState();
}

class _PartnerRoutePdfThumbnailState extends State<PartnerRoutePdfThumbnail> {
  static final Map<String, Uint8List> _pngCache = {};

  Uint8List? _png;
  bool _loading = true;
  String? _error;
  bool _panning = false;
  Offset? _lastGlobal;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PartnerRoutePdfThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.share?.id != widget.share?.id ||
        oldWidget.bytes != widget.bytes) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _png = null;
    });

    try {
      final cacheKey = widget.share?.id ?? widget.bytes?.hashCode.toString();
      if (cacheKey != null && _pngCache.containsKey(cacheKey)) {
        if (mounted) {
          setState(() {
            _png = _pngCache[cacheKey];
            _loading = false;
          });
        }
        return;
      }

      Uint8List? pdfBytes = widget.bytes;
      if (pdfBytes == null || pdfBytes.isEmpty) {
        pdfBytes = RoutePdfBytesCache.forShare(
          widget.share?.id,
          widget.share?.pdfStoragePath,
        );
      }
      if ((pdfBytes == null || pdfBytes.isEmpty) && widget.share != null) {
        final path = widget.share!.pdfStoragePath.trim();
        if (path.isEmpty) throw StateError('PDF mangler');
        pdfBytes = await PartnerService.downloadRoutePdfBytes(path);
        if (pdfBytes != null && pdfBytes.isNotEmpty) {
          RoutePdfBytesCache.putShare(widget.share!.id, pdfBytes);
        }
      }
      if (pdfBytes == null || pdfBytes.isEmpty) {
        throw StateError('Kunne ikke hente PDF');
      }

      Uint8List? png;
      await for (final page in Printing.raster(pdfBytes, pages: [0], dpi: 110)) {
        png = await page.toPng();
        break;
      }

      if (png == null) throw StateError('Kunne ikke rendre forside');

      if (cacheKey != null) _pngCache[cacheKey] = png;

      if (mounted) {
        setState(() {
          _png = png;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Bad state: ', '');
          _loading = false;
        });
      }
    }
  }

  void _onLongPressStart(LongPressStartDetails d) {
    if (!widget.zoomTripHeader || _png == null) return;
    setState(() {
      _panning = true;
      _lastGlobal = d.globalPosition;
    });
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    if (!_panning || _lastGlobal == null) return;
    final delta = d.globalPosition - _lastGlobal!;
    _lastGlobal = d.globalPosition;
    // Dra høyre → mer venstre side synlig (sjåfør).
    RoutePdfThumbPanController.instance.nudge(
      Offset(-delta.dx / 280, -delta.dy / 320),
    );
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    if (!_panning) return;
    setState(() {
      _panning = false;
      _lastGlobal = null;
    });
  }

  Widget _buildPreviewStack() {
    final label = widget.driverLabel?.trim();

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_loading)
          const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_png != null)
          widget.zoomTripHeader
              ? ListenableBuilder(
                  listenable: RoutePdfThumbPanController.instance,
                  builder: (context, _) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        return _TripHeaderCrop(
                          png: _png!,
                          maxWidth: constraints.maxWidth,
                          maxHeight: constraints.maxHeight,
                          pan: RoutePdfThumbPanController.instance.pan,
                          highlight: _panning,
                        );
                      },
                    );
                  },
                )
              : widget.showFullPage
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 28),
                        child: Image.memory(_png!, fit: BoxFit.contain),
                      ),
                    )
                  : Image.memory(_png!, fit: BoxFit.cover)
        else
          Center(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.picture_as_pdf_outlined,
                      size: 32, color: Colors.grey.shade600),
                  const SizedBox(height: 6),
                  Text(
                    _error ?? 'Ingen forhåndsvisning',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        if (_panning)
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Text(
                    'Justerer alle ruter — dra for å se sjåfør/strekkode',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (label != null && label.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.78),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 20, 8, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.onTapOpen != null)
                        const Icon(Icons.zoom_in,
                            color: Colors.white70, size: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: widget.showFullPage ? Colors.grey.shade100 : Colors.grey.shade200,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _panning ? null : widget.onTapOpen,
        onLongPressStart: _onLongPressStart,
        onLongPressMoveUpdate: _onLongPressMove,
        onLongPressEnd: _onLongPressEnd,
        onLongPressCancel: () {
          if (_panning) {
            setState(() {
              _panning = false;
              _lastGlobal = null;
            });
          }
        },
        child: _buildPreviewStack(),
      ),
    );

    if (widget.height != null) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: child,
        ),
      );
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: child,
    );
  }
}

/// Topp-venstre utsnitt av SAP-forsiden (strekkode + sjåfør), samme for alle kort.
class _TripHeaderCrop extends StatelessWidget {
  final Uint8List png;
  final double maxWidth;
  final double maxHeight;
  final Offset pan;
  final bool highlight;

  /// Synlig topp-andel av A4 (lavere = mer zoom).
  static const double topFraction = 0.34;

  /// Synlig venstre-andel — holder sjåfør/strekkode i bildet.
  static const double leftFraction = 0.72;

  static const double a4HeightOverWidth = 1.414213562;

  const _TripHeaderCrop({
    required this.png,
    required this.maxWidth,
    required this.maxHeight,
    required this.pan,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final w = maxWidth;
    final h = maxHeight;
    if (w <= 0 || h <= 0) return const SizedBox.shrink();

    final pageH = w / leftFraction * a4HeightOverWidth;
    final cropW = w;
    final cropH = pageH * topFraction;

    // pan.dx negativ → Alignment mer til venstre
    final alignX = (-0.85 + pan.dx * 1.6).clamp(-1.0, 1.0);
    final alignY = (-1.0 + pan.dy * 1.4).clamp(-1.0, 1.0);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: highlight
            ? Border.all(color: Colors.lightBlueAccent, width: 2)
            : null,
      ),
      child: ClipRect(
        child: SizedBox(
          width: w,
          height: h,
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: Alignment(alignX, alignY),
            child: SizedBox(
              width: cropW,
              height: cropH,
              child: ClipRect(
                child: Align(
                  alignment: Alignment(alignX, alignY),
                  widthFactor: leftFraction,
                  heightFactor: topFraction,
                  child: Image.memory(
                    png,
                    width: w / leftFraction,
                    fit: BoxFit.fitWidth,
                    alignment: Alignment(alignX, alignY),
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
