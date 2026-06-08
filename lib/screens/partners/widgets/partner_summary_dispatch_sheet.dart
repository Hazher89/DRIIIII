import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/services/partner/partner_summary_service.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import 'partner_route_pdf_actions.dart';
import 'partner_route_workflow_ui.dart';
import 'partner_summary_queue_card.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

const _summaryCardGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 280,
  childAspectRatio: 0.54,
  crossAxisSpacing: 10,
  mainAxisSpacing: 10,
);

const _summaryAccent = Color(0xFF00695C);
const _summaryAccentDark = Color(0xFF004D40);

enum _SummaryTab { all, needsReview, selected }

enum _SummaryQueueFilter { all, needsReview, selected, ready }

/// Superadmin: last opp oppsummerings-PDF-er — samme layout som AUTO MASS / SAP.
class PartnerSummaryDispatchSheet extends StatefulWidget {
  const PartnerSummaryDispatchSheet({
    super.key,
    required this.partners,
    required this.vehiclesByPartner,
    required this.companyId,
  });

  final List<Partner> partners;
  final Map<String, List<PartnerVehicle>> vehiclesByPartner;
  final String companyId;

  static Future<bool?> show(
    BuildContext context, {
    required List<Partner> partners,
    required Map<String, List<PartnerVehicle>> vehiclesByPartner,
    required String companyId,
  }) {
    return showPartnerRouteWorkflowDialog<bool>(
      context,
      child: PartnerSummaryDispatchSheet(
        partners: partners,
        vehiclesByPartner: vehiclesByPartner,
        companyId: companyId,
      ),
    );
  }

  @override
  State<PartnerSummaryDispatchSheet> createState() => _PartnerSummaryDispatchSheetState();
}

class _PartnerSummaryDispatchSheetState extends State<PartnerSummaryDispatchSheet> {
  List<SummaryDispatchDraft> _drafts = [];
  bool _sendSms = true;
  bool _sending = false;
  bool _busyUpload = false;
  bool _guideExpanded = false;
  _SummaryTab _tab = _SummaryTab.all;
  _SummaryQueueFilter _filter = _SummaryQueueFilter.all;

  int get _selectedCount => _drafts.where((d) => d.selected).length;

  int get _needsReviewCount => _drafts.where((d) => d.needsReview).length;

  int get _readyCount =>
      _drafts.where((d) => d.selected && d.partnerId != null && !d.needsReview).length;

  List<SummaryDispatchDraft> get _visibleDrafts {
    Iterable<SummaryDispatchDraft> list = _drafts;
    switch (_tab) {
      case _SummaryTab.all:
        break;
      case _SummaryTab.needsReview:
        list = list.where((d) => d.needsReview);
      case _SummaryTab.selected:
        list = list.where((d) => d.selected);
    }
    switch (_filter) {
      case _SummaryQueueFilter.all:
        return list.toList();
      case _SummaryQueueFilter.needsReview:
        return list.where((d) => d.needsReview).toList();
      case _SummaryQueueFilter.selected:
        return list.where((d) => d.selected).toList();
      case _SummaryQueueFilter.ready:
        return list.where((d) => d.selected && d.partnerId != null && !d.needsReview).toList();
    }
  }

  int get _tabIndex {
    switch (_tab) {
      case _SummaryTab.all:
        return 0;
      case _SummaryTab.needsReview:
        return 1;
      case _SummaryTab.selected:
        return 2;
    }
  }

  void _setTabIndex(int i) {
    setState(() {
      _tab = switch (i) {
        1 => _SummaryTab.needsReview,
        2 => _SummaryTab.selected,
        _ => _SummaryTab.all,
      };
      if (_tab == _SummaryTab.needsReview) {
        _filter = _SummaryQueueFilter.needsReview;
      } else if (_tab == _SummaryTab.selected) {
        _filter = _SummaryQueueFilter.selected;
      } else {
        _filter = _SummaryQueueFilter.all;
      }
    });
  }

  Future<void> _pickPdfs() async {
    setState(() => _busyUpload = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        allowMultiple: true,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final files = <({String name, Uint8List bytes})>[];
      for (final f in picked.files) {
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        files.add((name: f.name, bytes: bytes));
      }
      if (files.isEmpty) return;

      setState(() {
        _drafts = PartnerSummaryService.buildDrafts(
          files: files,
          partners: widget.partners,
          vehiclesByPartner: widget.vehiclesByPartner,
        );
      });
    } finally {
      if (mounted) setState(() => _busyUpload = false);
    }
  }

  void _clearQueue() {
    setState(() => _drafts = []);
  }

  void _removeDraft(SummaryDispatchDraft draft) {
    setState(() => _drafts.removeWhere((d) => d.localId == draft.localId));
  }

  Partner? _partnerFor(SummaryDispatchDraft draft) {
    if (draft.partnerId == null) return null;
    return widget.partners.where((p) => p.id == draft.partnerId).firstOrNull;
  }

  Future<void> _showEditSheet(SummaryDispatchDraft draft) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
          ),
          child: SingleChildScrollView(
            child: PartnerSummaryQueueCard.buildDetailsForm(
              context: ctx,
              draft: draft,
              partners: widget.partners,
              accentDark: _summaryAccentDark,
              needsReview: draft.needsReview,
              onPartnerChanged: (v) {
                setSheet(() {
                  draft.partnerId = v;
                  draft.matchReason = 'Manuelt valgt';
                });
                setState(() {});
              },
              onWeekChanged: (v) => draft.weekLabel = v.trim(),
              onPreview: () => PartnerRoutePdfActions.openPdfBytes(
                ctx,
                bytes: draft.bytes,
                title: draft.fileName,
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _send({required bool withSms}) async {
    if (_selectedCount == 0) return;
    final unassigned = _drafts.where((d) => d.selected && d.partnerId == null).toList();
    if (unassigned.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${unassigned.length} valgte PDF-er mangler bedrift.')),
      );
      setState(() {
        _tab = _SummaryTab.needsReview;
        _filter = _SummaryQueueFilter.needsReview;
      });
      return;
    }

    final dupPartners = <String>{};
    final seen = <String>{};
    for (final d in _drafts.where((x) => x.selected && x.partnerId != null)) {
      if (!seen.add(d.partnerId!)) dupPartners.add(d.partnerId!);
    }
    if (dupPartners.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Flere PDF-er til samme bedrift?'),
          content: const Text(
            'Du har valgt mer enn én PDF til samme bedrift i én sending. '
            'Hver bedrift skal kun få sin egen oppsummering. Fortsette likevel?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send likevel')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _sending = true);
    final result = await PartnerSummaryService.sendSelected(
      companyId: widget.companyId,
      drafts: _drafts,
      partners: widget.partners,
      sendSms: withSms,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    final msg = StringBuffer('Sendt til ${result.sent} bedrift(er).');
    if (result.errors.isNotEmpty) {
      msg.write('\n${result.errors.take(3).join('\n')}');
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.toString())));
    if (result.sent > 0) Navigator.pop(context, true);
  }

  String _tabHint() {
    switch (_tab) {
      case _SummaryTab.all:
        return 'Se PDF-forside på hvert kort før du sender. Trykk kort for detaljer og bedriftsvalg.';
      case _SummaryTab.needsReview:
        return 'PDF-er som mangler sikker matching — velg riktig bedrift før sending.';
      case _SummaryTab.selected:
        return 'Kun valgte oppsummeringer sendes til bil-eier-portalen.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _drafts.isNotEmpty &&
        _selectedCount > 0 &&
        !_drafts.any((d) => d.selected && d.partnerId == null);

    return PartnerRouteWorkflowShell(
      accent: _summaryAccent,
      accentDark: _summaryAccentDark,
      icon: Icons.summarize_outlined,
      title: 'Send ut oppsummeringer',
      subtitle: 'Kun superadmin · hver bedrift får kun sin egen PDF · sjekk forsiden før sending',
      badge: 'ØKONOMI',
      metrics: [
        RouteWorkflowMetric(
          label: 'PDF-er',
          value: '${_drafts.length}',
          icon: Icons.description_outlined,
          color: _summaryAccentDark,
        ),
        RouteWorkflowMetric(
          label: 'Valgt',
          value: '$_selectedCount',
          icon: Icons.check_box_outlined,
          color: Colors.blueGrey.shade700,
        ),
        RouteWorkflowMetric(
          label: 'Klare',
          value: '$_readyCount',
          icon: Icons.check_circle_outline,
          color: Colors.green.shade700,
        ),
        if (_needsReviewCount > 0)
          RouteWorkflowMetric(
            label: 'Trenger deg',
            value: '$_needsReviewCount',
            icon: Icons.warning_amber_rounded,
            color: Colors.orange.shade800,
          ),
      ],
      sidebar: _buildSidebar(),
      guidePanel: _buildGuide(),
      guideExpanded: _guideExpanded,
      onGuideToggle: () => setState(() => _guideExpanded = !_guideExpanded),
      tabLabels: const ['Alle', 'Trenger deg', 'Valgt'],
      tabBadges: [
        _drafts.isNotEmpty ? _drafts.length : null,
        _needsReviewCount > 0 ? _needsReviewCount : null,
        _selectedCount > 0 ? _selectedCount : null,
      ],
      tabBadgeColors: [
        _summaryAccentDark,
        Colors.orange.shade800,
        Colors.green.shade700,
      ],
      selectedTabIndex: _tabIndex,
      onTabSelected: _setTabIndex,
      tabCaption: _tabHint(),
      showTabCaption: true,
      tabBody: _buildTabBody(),
      footer: _buildFooter(canSend),
      topBanner: _needsReviewCount > 0 && _tab != _SummaryTab.needsReview
          ? routeManualAttentionBanner(
              count: _needsReviewCount,
              onOpenManual: () => _setTabIndex(1),
            )
          : null,
    );
  }

  Widget _buildSidebar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _busyUpload || _sending ? null : _pickPdfs,
          style: FilledButton.styleFrom(
            backgroundColor: _summaryAccentDark,
            minimumSize: const Size(double.infinity, 50),
          ),
          icon: _busyUpload
              ? SizedBox(width: 18, height: 18, child: DriftProLoadingIndicator(size: 18))
              : const Icon(Icons.upload_file),
          label: Text(_drafts.isEmpty ? 'Velg PDF-er' : 'Last opp flere PDF-er'),
        ),
        if (_drafts.isNotEmpty) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _sending ? null : _clearQueue,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: Text('Tøm kø (${_drafts.length})'),
            style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _sending
                      ? null
                      : () => setState(() {
                            for (final d in _drafts) {
                              d.selected = true;
                            }
                          }),
                  child: const Text('Huk på alle'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _sending
                      ? null
                      : () => setState(() {
                            for (final d in _drafts) {
                              d.selected = false;
                            }
                          }),
                  child: const Text('Huk av alle'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('SMS-varsel', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(
              _sendSms ? 'Bedrift får SMS når oppsummering er klar' : 'Kun portal — uten SMS',
              style: const TextStyle(fontSize: 11),
            ),
            value: _sendSms,
            activeThumbColor: _summaryAccent,
            onChanged: _sending ? null : (v) => setState(() => _sendSms = v),
          ),
        ],
      ],
    );
  }

  Widget _buildGuide() {
    const steps = [
      'Last opp én eller flere oppsummerings-PDF-er.',
      'Systemet leser uke, bedrift, beløp og matcher mot DriftPro.',
      'Sjekk PDF-forsiden på kortene — trykk for å åpne eller redigere.',
      'Velg riktig bedrift der matching er usikker.',
      'Send med eller uten SMS-varsel til bil-eier.',
    ];
    return Material(
      color: _summaryAccent.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: steps.asMap().entries.map((e) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: _summaryAccent,
                    child: Text(
                      '${e.key + 1}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(e.value, style: const TextStyle(fontSize: 12, height: 1.35))),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ChoiceChip(
          label: Text('Alle (${_drafts.length})'),
          selected: _filter == _SummaryQueueFilter.all,
          onSelected: (_) => setState(() => _filter = _SummaryQueueFilter.all),
        ),
        ChoiceChip(
          label: Text('Trenger deg ($_needsReviewCount)'),
          selected: _filter == _SummaryQueueFilter.needsReview,
          onSelected: (_) => setState(() => _filter = _SummaryQueueFilter.needsReview),
        ),
        ChoiceChip(
          label: Text('Valgt ($_selectedCount)'),
          selected: _filter == _SummaryQueueFilter.selected,
          onSelected: (_) => setState(() => _filter = _SummaryQueueFilter.selected),
        ),
        ChoiceChip(
          label: Text('Klare ($_readyCount)'),
          selected: _filter == _SummaryQueueFilter.ready,
          onSelected: (_) => setState(() => _filter = _SummaryQueueFilter.ready),
        ),
      ],
    );
  }

  Widget _buildTabBody() {
    if (_drafts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.summarize_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'Last opp oppsummerings-PDF-er',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 8),
              Text(
                'Samme arbeidsflyt som AUTO MASS og SAP:\n'
                'se alle PDF-er som kort, kontroller matching, send når alt stemmer.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, height: 1.45),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busyUpload ? null : _pickPdfs,
                style: FilledButton.styleFrom(backgroundColor: _summaryAccentDark),
                icon: const Icon(Icons.upload_file),
                label: const Text('Velg PDF-er'),
              ),
            ],
          ),
        ),
      );
    }

    final visible = _visibleDrafts;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: _buildFilterBar(),
          ),
        ),
        if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                'Ingen PDF-er matcher filteret.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            sliver: SliverGrid(
              gridDelegate: _summaryCardGridDelegate,
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final draft = visible[i];
                  return PartnerSummaryQueueCard(
                    draft: draft,
                    partner: _partnerFor(draft),
                    accent: _summaryAccent,
                    accentDark: _summaryAccentDark,
                    checked: draft.selected,
                    needsReview: draft.needsReview,
                    busy: _sending,
                    onChecked: (v) => setState(() => draft.selected = v ?? false),
                    onRemove: () => _removeDraft(draft),
                    onOpenDetails: () => _showEditSheet(draft),
                  );
                },
                childCount: visible.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFooter(bool canSend) {
    final unassigned = _drafts.where((d) => d.selected && d.partnerId == null).length;
    final statusText = _drafts.isEmpty
        ? 'Ingen PDF-er i kø'
        : unassigned > 0
            ? '$unassigned valgte PDF-er mangler bedrift'
            : canSend
                ? 'Sjekk PDF-forside på kortene før sending · $_selectedCount valgt'
                : 'Velg PDF-er og bedrift før sending';

    final btnNoSms = FilledButton.icon(
      onPressed: _sending || !canSend ? null : () => _send(withSms: false),
      icon: _sending
          ? SizedBox(width: 16, height: 16, child: DriftProLoadingIndicator(size: 16))
          : const Icon(Icons.inventory_2_outlined, size: 20),
      label: Text('Uten SMS ($_selectedCount)'),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.blueGrey.shade600,
        minimumSize: const Size(0, 46),
      ),
    );

    final btnSms = FilledButton.icon(
      onPressed: _sending || !canSend ? null : () => _send(withSms: true),
      icon: _sending
          ? SizedBox(width: 16, height: 16, child: DriftProLoadingIndicator(size: 16))
          : const Icon(Icons.rocket_launch_outlined, size: 20),
      label: Text('Med SMS ($_selectedCount)'),
      style: FilledButton.styleFrom(
        backgroundColor: _summaryAccentDark,
        minimumSize: const Size(0, 46),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 640;
        final status = Text(
          statusText,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: unassigned > 0 ? Colors.orange.shade900 : Colors.grey.shade800,
          ),
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              status,
              const SizedBox(height: 10),
              btnNoSms,
              const SizedBox(height: 8),
              btnSms,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: status),
            const SizedBox(width: 12),
            btnNoSms,
            const SizedBox(width: 8),
            btnSms,
          ],
        );
      },
    );
  }
}
