import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/case_trace/case_trace.dart';
import '../../../core/services/partner/partner_deduction_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_deduction_case.dart';
import '../widgets/partner_portal_page_shell.dart';
import '../widgets/partner_modern_ui.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import 'owner_portal_deduction_detail_sheet.dart';

/// Bil-eier: arkiv over alle trekk — kun lesing, mobiloptimalisert.
class OwnerPortalDeductionsPage extends StatefulWidget {
  const OwnerPortalDeductionsPage({super.key, required this.partner});

  final Partner partner;

  @override
  State<OwnerPortalDeductionsPage> createState() => _OwnerPortalDeductionsPageState();
}

class _OwnerPortalDeductionsPageState extends State<OwnerPortalDeductionsPage> {
  List<PartnerDeductionCase> _cases = [];
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await PartnerDeductionService.listCasesPortal(partnerId: widget.partner.id);
      if (!mounted) return;
      setState(() {
        _cases = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<PartnerDeductionCase> get _filtered {
    final q = _searchCtrl.text.trim();
    return _cases.where((c) {
      return CaseTrace.matchesQuery(
        query: q,
        traceRef: c.displayTraceRef,
        caseNumber: c.caseNumber,
        id: c.id,
        title: c.templateTitle,
        logiqrmaCaseNumber: c.logiqrmaCaseNumber,
        voucherNumber: c.voucherNumber,
      ) || (c.comment ?? '').toLowerCase().contains(q.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'nb_NO', symbol: 'kr', decimalDigits: 0);
    final df = DateFormat('dd.MM.yyyy');
    final bottomPad = MediaQuery.paddingOf(context).bottom + 76;
    final filtered = _filtered;

    return PartnerPortalPageShell(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0F1419)
          : const Color(0xFFF3F4F6),
      title: 'Trekk',
      actions: [
        IconButton(tooltip: 'Oppdater', icon: const Icon(Icons.refresh), onPressed: _load),
      ],
      body: _loading
          ? const DriftProLoadingCenter()
          : _error != null
              ? _errorState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF9A3412), Color(0xFFEA580C)],
                              ),
                            ),
                            child: Text(
                              'Her ser du alle trekk MAVI har registrert mot ${widget.partner.name}. '
                              'Trykk en sak for saksnummer, begrunnelse, kommentarer og bevis.',
                              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.45),
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: 'Søk saksnummer, beløp, tema …',
                              prefixIcon: const Icon(Icons.search),
                              filled: true,
                              fillColor: PartnerModernUi.surface(context),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Text(
                            '${filtered.length} trekk i arkivet',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: PartnerModernUi.muted(context),
                            ),
                          ),
                        ),
                      ),
                      if (filtered.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                _cases.isEmpty
                                    ? 'Ingen registrerte trekk ennå.'
                                    : 'Ingen treff på søket.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: PartnerModernUi.muted(context)),
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, i) {
                                final c = filtered[i];
                                return _TrekkArchiveCard(
                                  caseRow: c,
                                  money: money,
                                  dateLabel: df.format(c.createdAt),
                                  onTap: () => OwnerPortalDeductionDetailSheet.show(context, c),
                                );
                              },
                              childCount: filtered.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.orange),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Prøv igjen'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrekkArchiveCard extends StatelessWidget {
  const _TrekkArchiveCard({
    required this.caseRow,
    required this.money,
    required this.dateLabel,
    required this.onTap,
  });

  final PartnerDeductionCase caseRow;
  final NumberFormat money;
  final String dateLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = caseRow;
    final muted = PartnerModernUi.muted(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF9A3412).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.gavel_rounded, color: Color(0xFF9A3412)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.displayTraceRef,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                            ),
                          ),
                          Text(
                            money.format(c.amountNok),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: DriftProTheme.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        c.templateTitle,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        c.shortDescription,
                        style: TextStyle(fontSize: 12, color: muted, height: 1.3),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 13, color: muted),
                          const SizedBox(width: 4),
                          Text(dateLabel, style: TextStyle(fontSize: 11, color: muted)),
                          if (c.evidenceCount > 0) ...[
                            const SizedBox(width: 12),
                            Icon(Icons.photo_library_outlined, size: 13, color: muted),
                            const SizedBox(width: 4),
                            Text('${c.evidenceCount} bevis', style: TextStyle(fontSize: 11, color: muted)),
                          ],
                          if (c.comment?.isNotEmpty == true) ...[
                            const SizedBox(width: 12),
                            Icon(Icons.chat_bubble_outline, size: 13, color: muted),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
