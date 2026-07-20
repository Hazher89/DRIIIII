import 'package:flutter/material.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_summary_meta.dart';
import '../widgets/partner_portal_page_shell.dart';
import '../widgets/partner_ui.dart';
import 'owner_portal_economic_summary.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Økonomisk oppsummering fra PDF (siste uke, arkiv, måned/år-sum).
class OwnerPortalSummaryPage extends StatefulWidget {
  final Partner partner;
  const OwnerPortalSummaryPage({super.key, required this.partner});

  @override
  State<OwnerPortalSummaryPage> createState() => _OwnerPortalSummaryPageState();
}

class _OwnerPortalSummaryPageState extends State<OwnerPortalSummaryPage> {
  List<OwnerEconomicSummaryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final docs = await PartnerService.fetchOwnerPortalSummaryDocuments(widget.partner.id);
      if (mounted) {
        setState(() {
          _entries = parseEconomicSummaries(docs);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _allTimeTotal =>
      _entries.fold<double>(0, (sum, e) => sum + e.amount);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F1419) : const Color(0xFFF4F6F8);

    return PartnerPortalPageShell(
      backgroundColor: bg,
      title: 'Oppsummering',
      actions: [
        IconButton(tooltip: 'Oppdater', onPressed: _load, icon: const Icon(Icons.refresh)),
        IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () => signOutFromPortal(context),
        ),
      ],
      body: _loading
          ? const DriftProLoadingCenter()
          : RefreshIndicator(
              onRefresh: _load,
              child: _entries.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: [
                        Icon(Icons.summarize_outlined, size: 56, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        const Text(
                          'Ingen oppsummering delt ennå',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Når MAVI sender ukesoppsummering fra PDF, vises beløp, datoer og full oversikt her — '
                          'pluss arkiv og total inntekt per måned og år.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600, height: 1.4),
                        ),
                      ],
                    )
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Kun du og MAVI superadmin ser disse oppsummeringene. '
                            'Andre bedrifter og sjåfører har ikke tilgang.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: PartnerUi.mutedText(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (_entries.isNotEmpty) ...[
                          OwnerPortalEconomicSummaryHero(
                            entry: _entries.first,
                            onOpenPdf: () => openOwnerSummaryPdf(context, _entries.first.doc),
                          ),
                          const SizedBox(height: 20),
                          _allTimeBanner(),
                          const SizedBox(height: 8),
                          OwnerPortalEconomicTotalsSection(entries: _entries),
                          const SizedBox(height: 8),
                          OwnerPortalEconomicArchiveList(
                            entries: _entries,
                            onTap: (e) => showOwnerSummaryDetailSheet(context, e),
                          ),
                        ],
                      ],
                    ),
            ),
    );
  }

  Widget _allTimeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.savings_outlined, color: DriftProTheme.primaryGreenDark, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Totalt i portalen',
                  style: TextStyle(fontSize: 12, color: PartnerUi.mutedText(context)),
                ),
                Text(
                  '${PartnerSummaryMeta.formatAmount(_allTimeTotal)} kr eks mva',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                Text(
                  '${_entries.length} oppsummering${_entries.length == 1 ? '' : 'er'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
