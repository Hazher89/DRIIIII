import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/route_pdf_bytes_cache.dart';
import '../../../models/partner/partner_links.dart';

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
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    // Top-venstre: SAP Trip Overview har sjåfør/strekkode til venstre.
                    return ClipRect(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Transform.scale(
                          scale: 2.55,
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            width: w,
                            child: Image.memory(_png!, fit: BoxFit.fitWidth),
                          ),
                        ),
                      ),
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
        if (label != null && label.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
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
                      const Icon(Icons.zoom_in, color: Colors.white70, size: 16),
                  ],
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
      child: InkWell(
        onTap: widget.onTapOpen,
        child: _buildPreviewStack(),
      ),
    );

    if (widget.height != null) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: SizedBox(height: widget.height, width: double.infinity, child: child),
      );
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: child,
    );
  }
}
