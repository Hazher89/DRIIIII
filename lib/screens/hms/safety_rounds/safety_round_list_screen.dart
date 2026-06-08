import 'package:flutter/material.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/hms/safety_round_templates.dart';
import '../../../core/services/hms/safety_round_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/safety_round.dart';
import 'package:intl/intl.dart';
import 'safety_round_conduct_screen.dart';
import 'safety_round_detail_screen.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

class SafetyRoundListScreen extends StatefulWidget {
  const SafetyRoundListScreen({super.key});

  @override
  State<SafetyRoundListScreen> createState() => _SafetyRoundListScreenState();
}

class _SafetyRoundListScreenState extends State<SafetyRoundListScreen> {
  List<SafetyRound> _rounds = [];
  bool _isLoading = true;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId != null) {
        final data = await SafetyRoundService.fetchAll(
          companyId: companyId,
          search: _search.text,
        );
        setState(() => _rounds = data);
      } else {
        setState(() => _rounds = []);
      }
    } catch (_) {
      // Handle error
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Vernerunder – arkiv'),
        actions: [
          IconButton(icon: const Icon(AppIcons.add), onPressed: () => _createNew(context)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Søk tittel, arkivnr, sted, ansvarlig...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _search.clear();
                    _loadData();
                  },
                ),
                filled: true,
                fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _loadData(),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const DriftProLoadingCenter()
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: _rounds.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _rounds.length,
                            itemBuilder: (context, index) {
                              return _buildCard(_rounds[index], isDark);
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(AppIcons.safetyRound, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'Ingen vernerunder i arkivet',
            style: TextStyle(color: Colors.grey),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: ElevatedButton(
            onPressed: () => _createNew(context),
            child: const Text('START VERNERUNDE (NORSK LOV-MAL)'),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(SafetyRound r, bool isDark) {
    final isCompleted = r.overallStatus == 'fullført';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: DriftProTheme.cardShadow,
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: (isCompleted ? DriftProTheme.success : DriftProTheme.warning)
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isCompleted ? Icons.verified_outlined : AppIcons.safetyRound,
            color: isCompleted ? DriftProTheme.success : DriftProTheme.warning,
          ),
        ),
        title: Text(r.title, style: DriftProTheme.labelLg),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r.archiveNumber != null)
              Text('Arkiv: ${r.archiveNumber}', style: DriftProTheme.bodySm),
            Text(
              'Utført: ${r.conductorName ?? "Ukjent"}${r.signerRole != null ? " (${r.signerRole})" : ""}',
              style: DriftProTheme.bodySm,
            ),
            Text(
              r.completedAt != null
                  ? DateFormat('dd.MM.yyyy HH:mm').format(r.completedAt!)
                  : r.scheduledDate != null
                      ? 'Planlagt ${DateFormat('dd.MM.yyyy').format(r.scheduledDate!)}'
                      : 'Ikke fullført',
              style: DriftProTheme.bodySm,
            ),
            Text(
              'OK ${r.okCount} · Avvik ${r.avvikCount}',
              style: DriftProTheme.caption,
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (r.pdfUrl != null)
              const Icon(Icons.picture_as_pdf, size: 18, color: DriftProTheme.primaryGreen),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SafetyRoundDetailScreen(roundId: r.id),
            ),
          ).then((_) => _loadData());
        },
      ),
    );
  }

  void _createNew(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Velg vernerunde-mal', style: DriftProTheme.headingSm),
            const SizedBox(height: 8),
            Text(
              'Hovedmalen dekker kontor, lager, rømning, brann, ansatte og organisering etter norsk krav.',
              style: DriftProTheme.caption,
            ),
            const SizedBox(height: 16),
            ...SafetyRoundTemplates.all.map((t) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.fact_check,
                      color: DriftProTheme.primaryGreen),
                  title: Text(t.title),
                  subtitle: Text(
                    '${t.sections.fold<int>(0, (s, sec) => s + sec.items.length)} sjekkpunkter · ${t.description}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SafetyRoundConductScreen(template: t),
                      ),
                    ).then((id) {
                      _loadData();
                      if (id != null && context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SafetyRoundDetailScreen(roundId: id),
                          ),
                        );
                      }
                    });
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
