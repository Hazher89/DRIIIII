import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/route_pdf_text_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner_links.dart';
import 'partner_route_pdf_actions.dart';

class _PdfSearchHit {
  final PartnerRouteShare share;
  final int score;
  final String snippet;

  const _PdfSearchHit({
    required this.share,
    required this.score,
    required this.snippet,
  });
}

/// Smart søk i alle indekserte rute-PDF-er.
class PartnerRoutePdfSearchPanel extends StatefulWidget {
  final List<FleetPartnerVehicleRow> fleet;
  final TextEditingController? searchController;
  final bool expanded;

  const PartnerRoutePdfSearchPanel({
    super.key,
    this.fleet = const [],
    this.searchController,
    this.expanded = false,
  });

  static Future<void> show(
    BuildContext context, {
    required List<FleetPartnerVehicleRow> fleet,
  }) {
    final size = MediaQuery.sizeOf(context);
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: SizedBox(
          width: (size.width - 32).clamp(320.0, 960.0),
          height: (size.height - 40).clamp(420.0, 900.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
                child: Row(
                  children: [
                    const Icon(Icons.manage_search_outlined, color: Color(0xFF1565C0)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Søk i rute-PDF',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Lukk',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Finn adresse, kunde, MAVI eller sted i alle indekserte rute-PDF-er.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: PartnerRoutePdfSearchPanel(fleet: fleet, expanded: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  State<PartnerRoutePdfSearchPanel> createState() => _PartnerRoutePdfSearchPanelState();
}

class _PartnerRoutePdfSearchPanelState extends State<PartnerRoutePdfSearchPanel> {
  late final TextEditingController _ctrl;
  late final bool _ownsCtrl;
  Timer? _debounce;
  bool _searching = false;
  List<_PdfSearchHit> _hits = [];
  List<PartnerRouteShare> _allShares = [];

  @override
  void initState() {
    super.initState();
    _ownsCtrl = widget.searchController == null;
    _ctrl = widget.searchController ?? TextEditingController();
    _ctrl.addListener(_onQueryChanged);
    _preload();
  }

  Future<void> _preload() async {
    final cid = await SupabaseService.getCurrentCompanyId();
    if (cid == null) return;
    final shares = await PartnerService.fetchRouteSharesForCompany(cid, limit: 600);
    if (mounted) setState(() => _allShares = shares);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.removeListener(_onQueryChanged);
    if (_ownsCtrl) _ctrl.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  String? _maviForShare(PartnerRouteShare share) {
    for (final row in widget.fleet) {
      if (row.vehicle.id == share.partnerVehicleId) {
        return MaviUnitCodes.normalize(row.vehicle.unitCode);
      }
    }
    return null;
  }

  Future<void> _runSearch() async {
    final q = _ctrl.text.trim();
    if (q.length < 2) {
      setState(() => _hits = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;

      var pool = await PartnerService.searchRoutePdfText(cid, q, limit: 80);
      if (pool.isEmpty) {
        pool = _allShares;
      }

      final hits = <_PdfSearchHit>[];
      for (final share in pool) {
        final text = share.pdfSearchText ?? '';
        final score = RoutePdfTextService.scoreMatch(
          query: q,
          pdfText: text,
          title: share.title,
          fileName: share.pdfStoragePath,
          maviCode: _maviForShare(share),
        );
        if (score < 8 && text.isNotEmpty && !text.toLowerCase().contains(q.toLowerCase())) {
          continue;
        }
        if (score == 0 && text.isEmpty) continue;
        hits.add(
          _PdfSearchHit(
            share: share,
            score: score,
            snippet: RoutePdfTextService.snippet(text, q),
          ),
        );
      }
      hits.sort((a, b) => b.score.compareTo(a.score));
      if (mounted) setState(() => _hits = hits.take(25).toList());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _openPdf(PartnerRouteShare share) async {
    await PartnerRoutePdfActions.openPdf(context, share);
  }

  Widget _hitCard(_PdfSearchHit hit) {
    final mavi = _maviForShare(hit.share);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Stack(
          alignment: Alignment.bottomRight,
          children: [
            const Icon(Icons.picture_as_pdf, color: Colors.red, size: 32),
            if (hit.score >= 50)
              const Icon(Icons.verified, color: DriftProTheme.primaryGreen, size: 14),
          ],
        ),
        title: Text(
          hit.share.title ?? 'Rute-PDF',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mavi != null)
              Text(mavi, style: const TextStyle(color: DriftProTheme.primaryGreen, fontSize: 12)),
            const SizedBox(height: 4),
            Text(hit.snippet, maxLines: 3, style: const TextStyle(fontSize: 11)),
            Text(
              'Treff-score ${hit.score}% · ${hit.share.dispatchStatus == 'staged' ? 'Ikke sendt' : 'Sendt'}',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.open_in_new),
          onPressed: () => _openPdf(hit.share),
        ),
        onTap: () => _openPdf(hit.share),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchField = TextField(
      controller: _ctrl,
      autofocus: widget.expanded,
      decoration: InputDecoration(
        hintText: 'Søk i alle rute-PDF-er (adresse, kunde, MAVI, sted…)',
        prefixIcon: const Icon(Icons.manage_search, color: DriftProTheme.primaryGreen),
        suffixIcon: _searching
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _ctrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _ctrl.clear();
                      setState(() => _hits = []);
                    },
                  )
                : null,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );

    final emptyHint = _ctrl.text.trim().length >= 2 && !_searching && _hits.isEmpty
        ? const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Ingen treff. Prøv gate, postnr, kundenavn eller MAVI.'),
          )
        : null;

    final hitWidgets = _hits.map(_hitCard).toList();

    if (!widget.expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          searchField,
          const SizedBox(height: 6),
          Text(
            'Jo mer du skriver, desto mer presise forslag. Systemet leser og lagrer PDF-tekst ved fordeling.',
            style: TextStyle(fontSize: 11, color: Colors.grey[700]),
          ),
          const SizedBox(height: 10),
          if (emptyHint != null) emptyHint,
          ...hitWidgets,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        searchField,
        const SizedBox(height: 8),
        Text(
          'Jo mer du skriver, desto mer presise forslag.',
          style: TextStyle(fontSize: 11, color: Colors.grey[700]),
        ),
        const SizedBox(height: 10),
        if (emptyHint != null) emptyHint,
        Expanded(
          child: ListView(
            children: hitWidgets,
          ),
        ),
      ],
    );
  }
}
