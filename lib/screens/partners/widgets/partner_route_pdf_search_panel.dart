import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

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
  final String? fo;
  final List<String> fus;
  final List<String> bilags;
  final String? driver;
  final List<RoutePdfCustomer> customers;
  final bool archived;

  const _PdfSearchHit({
    required this.share,
    required this.score,
    required this.snippet,
    this.fo,
    this.fus = const [],
    this.bilags = const [],
    this.driver,
    this.customers = const [],
    this.archived = false,
  });
}

/// Avansert sporingssøk i alle indekserte rute-PDF-er (inkl. arkiv-MAVI).
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
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: SizedBox(
          width: (size.width - 24).clamp(320.0, 1100.0),
          height: (size.height - 32).clamp(480.0, 960.0),
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
                        'Rute-sporing (PDF)',
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
                  'Søk på bilag, FO, FU, kundenavn, telefon, adresse, MAVI, sjåfør eller dato. '
                  'Inkluderer historiske Connecteam-arkiv når de er importert.',
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
  DateTime? _fromDay;
  DateTime? _toDay;
  bool _includeArchive = true;
  _PdfSearchHit? _selected;

  static const _chipHints = [
    'Bilag',
    'FO',
    'FU',
    'Kundenavn',
    'Telefon',
    'MAVI',
    'Adresse',
  ];

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
    final shares = await PartnerService.fetchRouteSharesForCompany(cid, limit: 1200);
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
    final notes = share.notes ?? '';
    final m = RegExp(r'NO_O_M0*\d+', caseSensitive: false).firstMatch(notes);
    if (m != null) return MaviUnitCodes.normalize(m.group(0)!);
    final t = share.title ?? '';
    final tm = RegExp(r'(?:NO_O_)?M0*\d+', caseSensitive: false).firstMatch(t);
    if (tm != null) return MaviUnitCodes.normalize(tm.group(0)!);
    return null;
  }

  bool _isArchiveShare(PartnerRouteShare share) {
    final notes = (share.notes ?? '').toLowerCase();
    final title = (share.title ?? '').toLowerCase();
    return notes.contains('connecteam-arkiv') ||
        notes.contains('arkiv:') ||
        title.contains('arkiv');
  }

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDay ?? DateTime(2025, 1, 1),
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('nb', 'NO'),
      helpText: 'Fra dato',
    );
    if (picked == null) return;
    setState(() {
      _fromDay = DateTime(picked.year, picked.month, picked.day);
      if (_toDay != null && _toDay!.isBefore(_fromDay!)) _toDay = _fromDay;
    });
    _runSearch();
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDay ?? DateTime.now(),
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('nb', 'NO'),
      helpText: 'Til dato',
    );
    if (picked == null) return;
    setState(() {
      _toDay = DateTime(picked.year, picked.month, picked.day);
      if (_fromDay != null && _toDay!.isBefore(_fromDay!)) _fromDay = _toDay;
    });
    _runSearch();
  }

  Future<void> _runSearch() async {
    final q = _ctrl.text.trim();
    if (q.length < 2) {
      setState(() {
        _hits = [];
        _selected = null;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;

      var pool = await PartnerService.searchRoutePdfText(
        cid,
        q,
        limit: 120,
        fromDay: _fromDay,
        toDay: _toDay,
      );
      if (pool.isEmpty) {
        pool = _allShares.where((s) {
          if (_fromDay != null) {
            final d = DateTime(s.shareDate.year, s.shareDate.month, s.shareDate.day);
            if (d.isBefore(_fromDay!)) return false;
          }
          if (_toDay != null) {
            final d = DateTime(s.shareDate.year, s.shareDate.month, s.shareDate.day);
            if (d.isAfter(_toDay!)) return false;
          }
          return true;
        }).toList();
      }

      final hits = <_PdfSearchHit>[];
      final lower = q.toLowerCase();
      for (final share in pool) {
        final archived = _isArchiveShare(share);
        if (!_includeArchive && archived) continue;

        final text = share.pdfSearchText ?? '';
        final mavi = _maviForShare(share);
        final score = RoutePdfTextService.scoreMatch(
          query: q,
          pdfText: text,
          title: share.title,
          fileName: share.pdfStoragePath,
          maviCode: mavi,
        );
        final notesHit = (share.notes ?? '').toLowerCase().contains(lower);
        if (score < 8 &&
            text.isNotEmpty &&
            !text.toLowerCase().contains(lower) &&
            !notesHit) {
          continue;
        }
        if (score == 0 && text.isEmpty && !notesHit) continue;

        final ids = RoutePdfTextService.parseTrackingIds(text);
        final customers = text.isEmpty
            ? const <RoutePdfCustomer>[]
            : RoutePdfTextService.parseCustomers(text);

        hits.add(
          _PdfSearchHit(
            share: share,
            score: score == 0 && notesHit ? 20 : score,
            snippet: RoutePdfTextService.snippet(text, q),
            fo: ids.fo,
            fus: ids.fus,
            bilags: ids.bilags,
            driver: ids.driver,
            customers: customers,
            archived: archived,
          ),
        );
      }
      hits.sort((a, b) => b.score.compareTo(a.score));
      if (mounted) {
        setState(() {
          _hits = hits.take(40).toList();
          _selected = _hits.isEmpty ? null : _hits.first;
        });
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _openPdf(PartnerRouteShare share) async {
    await PartnerRoutePdfActions.openPdf(context, share);
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label kopiert'), duration: const Duration(seconds: 1)),
    );
  }

  Widget _hitCard(_PdfSearchHit hit) {
    final mavi = _maviForShare(hit.share);
    final selected = _selected?.share.id == hit.share.id;
    final df = DateFormat('dd.MM.yyyy');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? const Color(0xFFE3F2FD) : null,
      child: InkWell(
        onTap: () => setState(() => _selected = hit),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.picture_as_pdf, color: Colors.red, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hit.share.title ?? 'Rute-PDF',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                  if (hit.archived)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.brown.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Arkiv',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.brown.shade800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _chip(df.format(hit.share.shareDate), Icons.event),
                  if (mavi != null) _chip(mavi, Icons.local_shipping_outlined),
                  if (hit.fo != null) _chip('FO ${hit.fo}', Icons.qr_code_2),
                  if (hit.bilags.isNotEmpty) _chip('Bilag ${hit.bilags.first}', Icons.receipt_long),
                  if (hit.fus.isNotEmpty) _chip('FU ${hit.fus.first}', Icons.inventory_2_outlined),
                  if (hit.driver != null) _chip(hit.driver!, Icons.person_outline),
                  _chip('${hit.customers.length} kunder', Icons.people_outline),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                hit.snippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String t, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey.shade700),
          const SizedBox(width: 3),
          Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _detailPane(_PdfSearchHit hit) {
    final mavi = _maviForShare(hit.share);
    final df = DateFormat('EEEE d. MMMM yyyy', 'nb_NO');
    return ListView(
      padding: const EdgeInsets.all(4),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                hit.share.title ?? 'Rute',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _openPdf(hit.share),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Åpne PDF'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          df.format(hit.share.shareDate),
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
        if (hit.archived)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Historisk Connecteam-arkiv — sjåfør/MAVI finnes ikke i dagens aktive flåte.',
              style: TextStyle(fontSize: 11, color: Colors.brown.shade800),
            ),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (mavi != null) _copyTile('MAVI', mavi),
            if (hit.fo != null) _copyTile('Freight Order', hit.fo!),
            if (hit.driver != null) _copyTile('Sjåfør (PDF)', hit.driver!),
            ...hit.bilags.take(6).map((b) => _copyTile('Bilag', b)),
            ...hit.fus.take(6).map((f) => _copyTile('Freight Unit', f)),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Kunder i PDF (${hit.customers.length})',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        const SizedBox(height: 6),
        if (hit.customers.isEmpty)
          Text(
            'Ingen kundeliste ekstrahert — åpne PDF for full detalj.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          )
        else
          ...hit.customers.map((c) {
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text(
                  '${c.sequence}. ${c.name}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((c.addressHint ?? '').isNotEmpty)
                      Text(c.addressHint!, style: const TextStyle(fontSize: 11)),
                    if (c.phoneDisplay.isNotEmpty)
                      Text(c.phoneDisplay, style: const TextStyle(fontSize: 11)),
                    Wrap(
                      spacing: 6,
                      children: [
                        if ((c.freightUnit ?? '').isNotEmpty)
                          Text('FU ${c.freightUnit}', style: const TextStyle(fontSize: 10)),
                        if ((c.salesOrder ?? '').isNotEmpty)
                          Text('Bilag ${c.salesOrder}', style: const TextStyle(fontSize: 10)),
                        if ((c.deliveryWindow ?? '').isNotEmpty)
                          Text(c.deliveryWindow!, style: const TextStyle(fontSize: 10)),
                      ],
                    ),
                  ],
                ),
                trailing: c.phoneDisplay.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Kopier telefon',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () => _copy('Telefon', c.phoneDisplay),
                      ),
              ),
            );
          }),
      ],
    );
  }

  Widget _copyTile(String label, String value) {
    return InkWell(
      onTap: () => _copy(label, value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(width: 4),
                Icon(Icons.copy, size: 14, color: Colors.grey[600]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d. MMM yyyy', 'nb_NO');
    final searchField = TextField(
      controller: _ctrl,
      autofocus: widget.expanded,
      decoration: InputDecoration(
        hintText: 'Bilag, FO, FU, kunde, tlf, adresse, MAVI, sjåfør…',
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
                      setState(() {
                        _hits = [];
                        _selected = null;
                      });
                    },
                  )
                : null,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );

    final filters = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: _pickFrom,
          icon: const Icon(Icons.calendar_month, size: 16),
          label: Text(_fromDay == null ? 'Fra dato' : df.format(_fromDay!)),
        ),
        OutlinedButton.icon(
          onPressed: _pickTo,
          icon: const Icon(Icons.event, size: 16),
          label: Text(_toDay == null ? 'Til dato' : df.format(_toDay!)),
        ),
        if (_fromDay != null || _toDay != null)
          TextButton(
            onPressed: () {
              setState(() {
                _fromDay = null;
                _toDay = null;
              });
              _runSearch();
            },
            child: const Text('Nullstill dato'),
          ),
        FilterChip(
          label: const Text('Inkluder arkiv-MAVI', style: TextStyle(fontSize: 11)),
          selected: _includeArchive,
          onSelected: (v) {
            setState(() => _includeArchive = v);
            _runSearch();
          },
        ),
        ..._chipHints.map(
          (h) => ActionChip(
            label: Text(h, style: const TextStyle(fontSize: 10)),
            onPressed: () {
              // Bare hint — bruker skriver selv
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Skriv $h-nummer eller navn i søkefeltet'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
        ),
      ],
    );

    final qTrim = _ctrl.text.trim();
    final looksLikeBilag = RegExp(r'^2\d{9}$').hasMatch(qTrim);
    final emptyHint = qTrim.length >= 2 && !_searching && _hits.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              looksLikeBilag
                  ? 'Fant ikke bilag $qTrim i importerte rute-PDF-er. '
                      'Nummeret finnes ikke i Connecteam-filene vi har lastet ned — '
                      'det kan være SAP/annen kilde, eller PDF-en er ikke eksportert ennå.'
                  : 'Ingen treff. Prøv bilag, FO, FU, kundenavn, telefon, MAVI — '
                      'eller fjern datofilter. Historikk krever at Connecteam-arkiv er importert.',
            ),
          )
        : null;

    if (!widget.expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          searchField,
          const SizedBox(height: 8),
          filters,
          const SizedBox(height: 8),
          if (emptyHint != null) emptyHint,
          ..._hits.take(8).map(_hitCard),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        searchField,
        const SizedBox(height: 8),
        filters,
        const SizedBox(height: 8),
        if (emptyHint != null) emptyHint,
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 720;
              if (!wide) {
                return ListView(
                  children: [
                    ..._hits.map(_hitCard),
                    if (_selected != null) ...[
                      const Divider(),
                      SizedBox(height: 360, child: _detailPane(_selected!)),
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: ListView(children: _hits.map(_hitCard).toList()),
                  ),
                  const VerticalDivider(width: 16),
                  Expanded(
                    flex: 6,
                    child: _selected == null
                        ? Center(
                            child: Text(
                              'Velg et treff for FO/FU/bilag og kundedetaljer',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          )
                        : _detailPane(_selected!),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
